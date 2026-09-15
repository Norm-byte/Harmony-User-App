import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/home_speaker_state.dart';
import '../services/media_vault_service.dart';
import '../services/notification_service.dart';
import '../services/profanity_service.dart';
import '../services/translation_service.dart';
import '../services/usage_service.dart';
import '../services/user_service.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/live_room_counter_badge.dart';
import '../widgets/threaded_replies_panel.dart';
import '../widgets/translatable_text.dart';
import '../constants/report_reasons.dart';

class CommunityRoomScreen extends StatefulWidget {
  final Map<String, dynamic>? preselectedVaultImage;
  final bool showAppBar;

  const CommunityRoomScreen({
    super.key,
    this.preselectedVaultImage,
    this.showAppBar = false,
  });

  @override
  State<CommunityRoomScreen> createState() => _CommunityRoomScreenState();
}

class _CommunityRoomScreenState extends State<CommunityRoomScreen>
    with WidgetsBindingObserver {
  static const int _maximumImagesPerPost = 5;
  final TextEditingController _postController = TextEditingController();
  final ScrollController _feedScrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final MediaVaultService _mediaVaultService = MediaVaultService();
  final Map<String, Future<String>> _resolvedNameFutureByUserId = {};
  final Set<String> _expandedReplyPostIds = {};
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _communityPostsStream;

  UsageService? _usageService;
  final List<XFile> _pendingPickedImages = <XFile>[];
  final List<Map<String, dynamic>> _pendingVaultImages = <Map<String, dynamic>>[];
  final Map<String, Future<Uint8List>> _pendingPreviewFutureByPath = {};
  bool _saveCameraToVault = true;
  bool _isPosting = false;
  bool _isSupportRequest = false;
  String? _postingStatus;
  bool _isLoadingImageUsage = false;
  int _messagesRemaining = 0;
  int _dailyLimit = 5;
  int _imageUploadsUsedThisMonth = 0;
  Map<String, String>? _pendingNotificationTarget;
  String? _highlightedPostId;
  Timer? _highlightClearTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _communityPostsStream = FirebaseFirestore.instance
        .collection('community_posts')
        .orderBy('timestamp', descending: true)
        .snapshots();
    TranslationService.instance.init();
    unawaited(NotificationService().refreshCommunityNotificationBindings());
    if (widget.preselectedVaultImage != null) {
      _pendingVaultImages.add(Map<String, dynamic>.from(
        widget.preselectedVaultImage!,
      ));
    }
    NotificationService.communityNotificationTarget.addListener(
      _handleCommunityNotificationTarget,
    );
    _handleCommunityNotificationTarget();
  }

  void _handleCommunityNotificationTarget() {
    final target = NotificationService.communityNotificationTarget.value;
    if (target == null) return;
    NotificationService.communityNotificationTarget.value = null;
    if (!mounted) return;
    setState(() => _pendingNotificationTarget = target);
  }

  void _scrollToAndHighlightPendingTarget(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> posts,
  ) {
    final target = _pendingNotificationTarget;
    if (target == null) return;
    final postId = target['postId'];
    final index = posts.indexWhere((doc) => doc.id == postId);
    if (index == -1) return;
    _pendingNotificationTarget = null;
    final replyId = target['replyId'];
    if (replyId != null && postId != null) {
      _expandedReplyPostIds.add(postId);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_feedScrollController.hasClients) return;
      final estimatedOffset = index * 260.0;
      final target = estimatedOffset.clamp(
        0.0,
        _feedScrollController.position.maxScrollExtent,
      );
      _feedScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _highlightedPostId = postId);
      _highlightClearTimer?.cancel();
      _highlightClearTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _highlightedPostId = null);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newService = context.read<UsageService>();
    if (_usageService != newService) {
      _usageService?.removeListener(_calculateRemaining);
      _usageService = newService;
      _usageService?.addListener(_calculateRemaining);
      unawaited(_calculateRemaining());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return;
    }
  }

  @override
  void dispose() {
    NotificationService.communityNotificationTarget.removeListener(
      _handleCommunityNotificationTarget,
    );
    _highlightClearTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _usageService?.removeListener(_calculateRemaining);
    _postController.dispose();
    _feedScrollController.dispose();
    super.dispose();
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  String _currentAuthUid() {
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  String _effectiveCurrentUserId() {
    final authUid = _currentAuthUid().trim();
    if (authUid.isNotEmpty) return authUid;
    return UserService().userId.trim();
  }

  Future<void> _toggleTranslation() async {
    final enabled = !TranslationService.instance.isEnabled;
    await TranslationService.instance.setEnabled(enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
            ? 'Translation is ON for Common Room (TR-V5).'
            : 'Translation is OFF for Common Room (TR-V5).',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTranslateToggle({
    double hitSize = 96,
    double iconSize = 20,
    bool useIconButton = false,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: TranslationService.instance.enabledNotifier,
      builder: (context, enabled, _) {
        if (useIconButton) {
          return IconButton(
            tooltip: enabled ? 'Disable Translation' : 'Enable Translation',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(_toggleTranslation()),
            icon: Icon(
              Icons.translate,
              size: iconSize,
              color: enabled ? Colors.greenAccent : Colors.white,
            ),
          );
        }
        return Semantics(
          button: true,
          label: enabled ? 'Disable Translation' : 'Enable Translation',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleTranslation,
            child: SizedBox(
              width: hitSize,
              height: hitSize,
              child: Center(
                child: Icon(
                  Icons.translate,
                  size: iconSize,
                  color: enabled ? Colors.greenAccent : Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _calculateRemaining() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final lastResetStr = prefs.getString('chat_daily_limit_date');

    if (lastResetStr != todayStr) {
      await prefs.setInt('chat_messages_sent_today', 0);
      await prefs.setString('chat_daily_limit_date', todayStr);
      await prefs.remove('chat_messages_remaining');
    } else if (prefs.containsKey('chat_messages_remaining') &&
        !prefs.containsKey('chat_messages_sent_today')) {
      await prefs.setInt('chat_messages_sent_today', 0);
      await prefs.remove('chat_messages_remaining');
    }

    final sentToday = prefs.getInt('chat_messages_sent_today') ?? 0;
    final limit = _usageService?.maxDailySends ?? 5;

    if (!mounted) return;
    setState(() {
      _dailyLimit = limit;
      _messagesRemaining = (limit - sentToday).clamp(0, 9999);
    });

    unawaited(_refreshImageUsageCounter());
  }

  Future<void> _refreshImageUsageCounter() async {
    final userId = _effectiveCurrentUserId();
    if (userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _imageUploadsUsedThisMonth = 0;
        _isLoadingImageUsage = false;
      });
      return;
    }

    final limit = _usageService?.monthlyImageUploadLimit ?? 0;
    if (limit <= 0) {
      if (!mounted) return;
      setState(() {
        _imageUploadsUsedThisMonth = 0;
        _isLoadingImageUsage = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isLoadingImageUsage = true);
    }

    try {
      final used = await _mediaVaultService.getSharedRoomUploadsForMonth(
        userId,
        DateTime.now(),
      );
      if (!mounted) return;
      setState(() => _imageUploadsUsedThisMonth = used);
    } catch (_) {
      // Keep existing count on transient errors.
    } finally {
      if (mounted) {
        setState(() => _isLoadingImageUsage = false);
      }
    }
  }

  Future<void> _decrementMessageLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final sent = (prefs.getInt('chat_messages_sent_today') ?? 0) + 1;
    await prefs.setInt('chat_messages_sent_today', sent);
    await _calculateRemaining();
  }

  Future<void> _recordImageQuotaAlert({
    required String userId,
    required int monthlyLimit,
    required int used,
  }) async {
    final monthKey = DateFormat('yyyy-MM').format(DateTime.now());
    await FirebaseFirestore.instance
        .collection('quota_alerts')
        .doc('${userId}_$monthKey')
        .set({
      'userId': userId,
      'alertType': 'community_image_uploads',
      'status': 'open',
      'monthlyLimit': monthlyLimit,
      'usedThisMonth': used,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> _canUploadMoreImages(String userId) async {
    final limit = _usageService?.monthlyImageUploadLimit ?? 0;
    if (limit < 0) return true;
    if (limit == 0) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Image Uploads Unavailable'),
          content: const Text(
            'Image uploads are not enabled for your current tier.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }

    try {
      final used = await _mediaVaultService.getSharedRoomUploadsForMonth(
        userId,
        DateTime.now(),
      );
      if (used >= limit) {
        unawaited(_recordImageQuotaAlert(
          userId: userId,
          monthlyLimit: limit,
          used: used,
        ));
        if (!mounted) return false;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Monthly Image Limit Reached'),
            content: const Text(
              'We are sorry, but your monthly image allowance has been reached. We have let the Harmony team know so we can keep improving the allowance for everyone. Thank you for your patience.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return false;
      }
    } catch (_) {
      return true;
    }
    return true;
  }

  String? _requireCurrentUserId() {
    final userId = _effectiveCurrentUserId();
    if (userId.isNotEmpty) return userId;
    return null;
  }

  bool get _hasPendingImages =>
      _pendingPickedImages.isNotEmpty || _pendingVaultImages.isNotEmpty;

    int get _pendingImageCount =>
      _pendingPickedImages.length + _pendingVaultImages.length;

    int _remainingImageSlots() {
    final monthlyLimit = _usageService?.monthlyImageUploadLimit ?? 0;
    final monthlyRemaining = monthlyLimit < 0
      ? _maximumImagesPerPost
      : (monthlyLimit - _imageUploadsUsedThisMonth).clamp(0, monthlyLimit);
    return (_maximumImagesPerPost - _pendingImageCount)
      .clamp(0, monthlyRemaining);
    }

  List<String> _extractMediaUrls(Map<String, dynamic> post) {
    final directUrls = post['mediaUrls'];
    if (directUrls is List) {
      final urls = directUrls
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (urls.isNotEmpty) return urls;
    }

    final legacyUrl = (post['imageUrl'] ?? '').toString().trim();
    if (legacyUrl.isNotEmpty) {
      return <String>[legacyUrl];
    }

    return const <String>[];
  }

  void _clearPendingImage() {
    if (!mounted) return;
    setState(() {
      _pendingPickedImages.clear();
      _pendingVaultImages.clear();
      _pendingPreviewFutureByPath.clear();
      _saveCameraToVault = true;
    });
  }

  void _removePendingImageAt(int index) {
    if (!mounted) return;
    setState(() {
      final total = _pendingPickedImages.length + _pendingVaultImages.length;
      if (index < 0 || index >= total) return;
      if (index < _pendingPickedImages.length) {
        _pendingPickedImages.removeAt(index);
      } else {
        final vaultIndex = index - _pendingPickedImages.length;
        _pendingVaultImages.removeAt(vaultIndex);
      }
      if (_pendingPickedImages.isEmpty && _pendingVaultImages.isEmpty) {
        _saveCameraToVault = true;
      }
    });
  }

  Future<Uint8List> _previewBytesFor(XFile image) {
    final key = image.path.isNotEmpty ? image.path : image.name;
    return _pendingPreviewFutureByPath.putIfAbsent(key, image.readAsBytes);
  }

  Future<PreparedImageData> _prepareImageWithRetry(
    XFile image,
    int imageNumber,
    int totalImages,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        if (!mounted) throw StateError('Posting was cancelled');
        setState(() {
          _postingStatus = attempt == 1
              ? 'Preparing image $imageNumber of $totalImages...'
              : 'Retrying image $imageNumber of $totalImages...';
        });
        return await _mediaVaultService.prepareImage(image).timeout(
          const Duration(minutes: 2),
        );
      } catch (error) {
        lastError = error;
        if (attempt == 2) rethrow;
      }
    }
    throw lastError ?? StateError('Image preparation failed');
  }

  Future<UploadedMediaRef> _uploadRoomImageWithRetry({
    required String userId,
    required PreparedImageData prepared,
    required int imageNumber,
    required int totalImages,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        if (!mounted) throw StateError('Posting was cancelled');
        setState(() {
          _postingStatus = attempt == 1
              ? 'Uploading image $imageNumber of $totalImages...'
              : 'Retrying upload $imageNumber of $totalImages...';
        });
        return await _mediaVaultService.uploadToRoom(
          roomId: 'community_room',
          uid: userId,
          prepared: prepared,
        );
      } catch (error) {
        lastError = error;
        if (attempt == 2) rethrow;
      }
    }
    throw lastError ?? StateError('Image upload failed');
  }

  Future<void> _pickFromCamera() async {
    final userId = _requireCurrentUserId();
    if (userId == null || !await _canUploadMoreImages(userId)) return;
    final picked = await _imagePicker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _pendingPickedImages.add(picked);
      _pendingVaultImages.clear();
      _saveCameraToVault = true;
    });
  }

  Future<void> _pickFromGallery() async {
    final userId = _requireCurrentUserId();
    if (userId == null || !await _canUploadMoreImages(userId)) return;
    final remainingSlots = _remainingImageSlots();
    if (remainingSlots <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image slots remain for this post.')),
      );
      return;
    }
    final picked = await _imagePicker.pickMultiImage(limit: remainingSlots);
    if (picked.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _pendingPickedImages.addAll(picked);
      _pendingVaultImages.clear();
      _saveCameraToVault = true;
    });
  }

  Future<void> _pickFromVault() async {
    final userId = _requireCurrentUserId();
    if (userId == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.65,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _mediaVaultService.watchVaultImages(userId),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? const [];
                final activeDocs = docs.where((doc) {
                  final data = doc.data();
                  final status = (data['status'] ?? 'active').toString();
                  final url = (data['downloadUrl'] ?? '').toString();
                  return status == 'active' && url.isNotEmpty;
                }).toList();

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (activeDocs.isEmpty) {
                  return const Center(
                    child: Text('No vault images yet. Add one from camera or gallery.'),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: activeDocs.length,
                  itemBuilder: (context, index) {
                    final doc = activeDocs[index];
                    final data = doc.data();
                    final url = (data['downloadUrl'] ?? '').toString();

                    return InkWell(
                      onTap: () {
                        if (!mounted) return;
                        final vaultEntry = {
                          'imageId': doc.id,
                          'downloadUrl': url,
                          'storagePath': (data['storagePath'] ?? '').toString(),
                          'bytes': (data['bytes'] as num?)?.toInt() ?? 0,
                          'width': (data['width'] as num?)?.toInt() ?? 0,
                          'height': (data['height'] as num?)?.toInt() ?? 0,
                        };
                        setState(() {
                          _pendingVaultImages.add(vaultEntry);
                          _pendingPickedImages.clear();
                        });
                        Navigator.of(sheetContext).pop();
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(url, fit: BoxFit.cover),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openImagePickerSheet() async {
    FocusScope.of(context).unfocus();
    const cameraChoice = 'camera';
    const galleryChoice = 'gallery';
    const vaultChoice = 'vault';

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Attach Images'),
        contentPadding: const EdgeInsets.only(top: 8, bottom: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.of(dialogContext).pop(cameraChoice),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Device Photos'),
              onTap: () => Navigator.of(dialogContext).pop(galleryChoice),
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('Choose from My Harmony Vault'),
              onTap: () => Navigator.of(dialogContext).pop(vaultChoice),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    switch (choice) {
      case cameraChoice:
        await _pickFromCamera();
        break;
      case galleryChoice:
        await _pickFromGallery();
        break;
      case vaultChoice:
        await _pickFromVault();
        break;
    }
  }

  Future<void> _submitPost() async {
    final content = _postController.text.trim();
    final hasPendingImage = _hasPendingImages;
    if (content.isEmpty && !hasPendingImage) return;

    await _calculateRemaining();

    final userService = UserService();
    if (await userService.isCurrentlySuspended()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account is suspended from community messaging. Please use Support chat in My Harmony for assistance.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (content.isNotEmpty && ProfanityService().hasProfanity(content)) {
      final userId = _effectiveCurrentUserId();
      final publicName = await userService.ensureRecognizedPublicDisplayName() ??
          UserService.sanitizePublicDisplayName(userService.userName);
      await FirebaseFirestore.instance.collection('moderation_queue').add({
        'content': content,
        'userId': userId,
        'userName': publicName,
        'source': 'Community Room',
        'type': 'content_flag',
        'targetKind': 'community_post',
        'timestamp': FieldValue.serverTimestamp(),
        'reason': 'Profanity Detected',
        'status': 'pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profanity detected. Message flagged for moderation.'),
          backgroundColor: Colors.orange,
        ),
      );
      _postController.clear();
      _clearPendingImage();
      return;
    }

    if (_messagesRemaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily message limit reached. Try again tomorrow!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final pendingPickedCount = _pendingPickedImages.length;
    final monthlyLimit = _usageService?.monthlyImageUploadLimit ?? 0;
    final monthlyRemaining = monthlyLimit < 0
        ? pendingPickedCount
        : (monthlyLimit - _imageUploadsUsedThisMonth).clamp(0, monthlyLimit);
    if (pendingPickedCount > monthlyRemaining) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This post has $pendingPickedCount device images, but only '
            '$monthlyRemaining monthly image uploads remain.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isPosting = true;
      _postingStatus = pendingPickedCount > 0
          ? 'Preparing $pendingPickedCount image${pendingPickedCount == 1 ? '' : 's'}...'
          : 'Sharing post...';
    });

    final uploadedRoomStoragePaths = <String>[];
    var uploadedRoomImageCount = 0;
    var postCreated = false;

    try {
      final authUid = _currentAuthUid();
      final userService = UserService();
      final userId = _effectiveCurrentUserId();
      if (userId.isEmpty) return;

      final publicName = await userService.ensureRecognizedPublicDisplayName();
      if (publicName == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your account username is not recognized. Messaging is disabled until your profile name is fixed.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final postData = <String, dynamic>{
        'content': content,
        'userId': userId,
        'authorUid': authUid.isNotEmpty ? authUid : userId,
        'userName': publicName,
        'userPhoto': userService.userPhoto,
        'timestamp': FieldValue.serverTimestamp(),
        if (_isSupportRequest) 'isSupportRequest': true,
        if (_isSupportRequest) 'supportTapCount': 0,
        if (_isSupportRequest) 'supportedBy': <String>[],
      };

      final allPendingVaultImages = <Map<String, dynamic>>[..._pendingVaultImages];
      final allPendingPickedImages = <XFile>[..._pendingPickedImages];
      final preparedImagesForVault = <PreparedImageData>[];

      if (allPendingVaultImages.isNotEmpty || allPendingPickedImages.isNotEmpty) {
        final mediaUrls = <String>[];
        final mediaMetadata = <Map<String, dynamic>>[];
        final expiryDays = (_usageService?.feedImageExpiryDays ?? 5).clamp(1, 90);

        for (final item in allPendingVaultImages) {
          final url = (item['downloadUrl'] ?? '').toString();
          if (url.isEmpty) continue;
          mediaUrls.add(url);
          mediaMetadata.add({
            'url': url,
            'storagePath': (item['storagePath'] ?? '').toString(),
            'bytes': (item['bytes'] as num?)?.toInt() ?? 0,
            'width': (item['width'] as num?)?.toInt() ?? 0,
            'height': (item['height'] as num?)?.toInt() ?? 0,
            'source': 'vault',
            'status': 'active',
            'createdAt': Timestamp.now(),
            'expiresAt': Timestamp.fromDate(
              DateTime.now().add(Duration(days: expiryDays)),
            ),
          });
        }

        for (var imageIndex = 0;
            imageIndex < allPendingPickedImages.length;
            imageIndex++) {
          final picked = allPendingPickedImages[imageIndex];
          final imageNumber = imageIndex + 1;
          if (!mounted) return;
          if (!await _canUploadMoreImages(userId)) return;
          final prepared = await _prepareImageWithRetry(
            picked,
            imageNumber,
            allPendingPickedImages.length,
          );
          if (_saveCameraToVault) {
            preparedImagesForVault.add(prepared);
          }
          final roomUpload = await _uploadRoomImageWithRetry(
            userId: userId,
            prepared: prepared,
            imageNumber: imageNumber,
            totalImages: allPendingPickedImages.length,
          );

          mediaUrls.add(roomUpload.downloadUrl);
          uploadedRoomStoragePaths.add(roomUpload.storagePath);
          uploadedRoomImageCount++;
          mediaMetadata.add({
            'url': roomUpload.downloadUrl,
            'storagePath': roomUpload.storagePath,
            'bytes': roomUpload.bytes,
            'width': roomUpload.width,
            'height': roomUpload.height,
            'source': 'upload',
            'status': 'active',
            'createdAt': Timestamp.now(),
            'expiresAt': Timestamp.fromDate(
              DateTime.now().add(Duration(days: expiryDays)),
            ),
          });

          unawaited(_refreshImageUsageCounter());
        }

        postData.addAll({
          'hasImage': true,
          'imageUrl': mediaUrls.first,
          'mediaUrls': mediaUrls,
          'mediaMetadata': mediaMetadata,
          'imageStoragePath': mediaMetadata.first['storagePath'],
          'imageBytes': mediaMetadata.first['bytes'],
          'imageWidth': mediaMetadata.first['width'],
          'imageHeight': mediaMetadata.first['height'],
          'imageCreatedAt': FieldValue.serverTimestamp(),
          'imageExpiresAt': Timestamp.fromDate(
            DateTime.now().add(Duration(days: expiryDays)),
          ),
          'imageStatus': 'active',
          'imageSource': mediaMetadata.first['source'],
        });
      }

      final newPostRef = await FirebaseFirestore.instance.collection('community_posts').add(postData);
      postCreated = true;
      if (_isSupportRequest) {
        // Permanent personal copy, independent of the live post's lifetime —
        // survives admin retention cleanup or the user deleting the original.
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('support_intents')
            .add({
          'postId': newPostRef.id,
          'content': content,
          'imageUrl': postData['imageUrl'],
          'createdAt': FieldValue.serverTimestamp(),
          'isRealized': false,
        });
      }
      if (mounted) setState(() => _isSupportRequest = false);
      if (uploadedRoomImageCount > 0) {
        await _mediaVaultService.incrementSharedRoomUploadsForMonth(
          userId,
          DateTime.now(),
          count: uploadedRoomImageCount,
        );
      }
      var vaultSaveFailures = 0;
      for (final prepared in preparedImagesForVault) {
        try {
          await _mediaVaultService.uploadToVault(
            uid: userId,
            prepared: prepared,
            source: 'community_post_auto_save',
          );
          await _mediaVaultService.incrementVaultUploadsForMonth(
            userId,
            DateTime.now(),
          );
        } catch (_) {
          vaultSaveFailures++;
        }
      }
      await _decrementMessageLimit();
      _postController.clear();
      _clearPendingImage();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            vaultSaveFailures == 0
                ? 'Post shared with the community and saved to My Harmony Vault.'
                : 'Post shared, but $vaultSaveFailures image${vaultSaveFailures == 1 ? '' : 's'} could not be saved to My Harmony Vault.',
          ),
        ),
      );
    } catch (e) {
      if (!postCreated) {
        for (final storagePath in uploadedRoomStoragePaths) {
          await _mediaVaultService.deleteRoomMedia(storagePath);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error posting: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
          _postingStatus = null;
        });
      }
    }
  }

  Future<void> _toggleLike(String docId, List<dynamic> likedBy) async {
    final uid = _effectiveCurrentUserId();
    if (uid.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('community_posts').doc(docId);
    if (likedBy.contains(uid)) {
      await docRef.update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove([uid]),
      });
    } else {
      await docRef.update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([uid]),
      });
    }
  }

  bool _isPostOwnedByCurrentUser(Map<String, dynamic> post) {
    final currentIds = <String>{
      _effectiveCurrentUserId().trim(),
      _currentAuthUid().trim(),
    }.where((id) => id.isNotEmpty).toSet();
    if (currentIds.isEmpty) return false;

    final postIds = <String>{
      (post['userId'] ?? '').toString().trim(),
      (post['authorUid'] ?? '').toString().trim(),
    }.where((id) => id.isNotEmpty).toSet();

    return currentIds.any(postIds.contains);
  }

  Future<void> _showEditPostComposer({
    required String postId,
    required String initialText,
    required bool hasImage,
  }) async {
    final content = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ReplyComposerRoute(
          title: 'Edit post',
          hintText: 'Update your message...',
          actionLabel: 'Save',
          initialText: initialText,
        ),
      ),
    );
    if (!mounted) return;

    final trimmed = (content ?? '').trim();
    if (trimmed.isEmpty && !hasImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A post without text must keep an image.')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('community_posts').doc(postId).update({
      'content': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _removePostImage({
    required String postId,
    required Map<String, dynamic> post,
  }) async {
    final currentContent = (post['content'] ?? '').toString().trim();
    if (currentContent.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add text before removing the image, or delete the post.')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('community_posts').doc(postId).update({
      'hasImage': false,
      'imageStatus': 'removed_by_owner',
      'imageRemovedAt': FieldValue.serverTimestamp(),
      'imageUrl': FieldValue.delete(),
      'imageStoragePath': FieldValue.delete(),
      'imageBytes': FieldValue.delete(),
      'imageWidth': FieldValue.delete(),
      'imageHeight': FieldValue.delete(),
      'imageCreatedAt': FieldValue.delete(),
      'imageExpiresAt': FieldValue.delete(),
      'imageSource': FieldValue.delete(),
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _confirmAndDeletePost(String postId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This will remove your post from Common Room.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;
    await FirebaseFirestore.instance.collection('community_posts').doc(postId).delete();
  }

  Future<Map<String, String>?> _promptReportDetails({required String label}) async {
    final reasons = kReportReasons;
    String? selectedReason;
    final detailsController = TextEditingController();

    try {
      final result = await showModalBottomSheet<Map<String, String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.grey.shade900,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) {
            final explanation = detailsController.text.trim();
            final canSubmit = selectedReason != null && explanation.length >= 8;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report this $label',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select a reason and add a short explanation for moderators.',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ...reasons.map(
                      (reason) => RadioListTile<String>(
                        value: reason.label,
                        groupValue: selectedReason,
                        title: Text(reason.label, style: const TextStyle(color: Colors.white70)),
                        subtitle: Text(reason.caption, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        activeColor: Colors.redAccent,
                        onChanged: (value) {
                          if (value != null) {
                            setModalState(() => selectedReason = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: detailsController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Required: brief details (min 8 characters)',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.25),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      explanation.length < 8
                          ? 'Please add at least 8 characters so moderators have context.'
                          : 'Looks good.',
                      style: TextStyle(
                        color: explanation.length < 8 ? Colors.orangeAccent : Colors.greenAccent,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white30),
                            ),
                            onPressed: () => Navigator.pop(ctx, null),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: canSubmit
                                ? () {
                                    Navigator.pop(ctx, {
                                      'reason': selectedReason!,
                                      'explanation': explanation,
                                    });
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Submit Report'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      return result;
    } finally {
      detailsController.dispose();
    }
  }

  String? _extractImageUrlForReport(Map<String, dynamic> item) {
    final candidates = [
      item['imageUrl'],
      item['downloadUrl'],
      item['mediaUrl'],
      item['thumbnailUrl'],
      item['image'],
    ];
    for (final candidate in candidates) {
      final url = candidate?.toString().trim() ?? '';
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  Future<void> _reportPost(String postId, Map<String, dynamic> post) async {
    final reporter = UserService();
    final reportedUserId =
        (post['authorUid'] ?? post['userId'] ?? '').toString().trim();
    final content = (post['content'] ?? '').toString().trim();
    if (reportedUserId.isEmpty || reportedUserId == reporter.userId.trim()) {
      return;
    }
    final reportDetails = await _promptReportDetails(label: 'post');
    if (reportDetails == null) return;

    final imageUrl = _extractImageUrlForReport(post);
    await reporter.reportContent(
      reportedUserId,
      content,
      reportDetails['reason']!,
      'Community Room',
      metadata: {
        'targetKind': 'community_post',
        'targetId': postId,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (imageUrl != null) 'thumbnailUrl': imageUrl,
        'reportExplanation': reportDetails['explanation']!,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report sent to moderation.')),
    );
  }

  CollectionReference<Map<String, dynamic>> _repliesCollection(String postId) {
    return FirebaseFirestore.instance
        .collection('community_posts')
        .doc(postId)
        .collection('replies');
  }

  void _toggleRepliesExpanded(String postId) {
    final priorOffset = _feedScrollController.hasClients
        ? _feedScrollController.offset
        : 0.0;

    setState(() {
      if (_expandedReplyPostIds.contains(postId)) {
        _expandedReplyPostIds.remove(postId);
      } else {
        _expandedReplyPostIds.add(postId);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_feedScrollController.hasClients) return;
      final maxOffset = _feedScrollController.position.maxScrollExtent;
      if (maxOffset <= 0) return;
      final safeOffset = priorOffset.clamp(0.0, maxOffset);
      if ((_feedScrollController.offset - safeOffset).abs() < 1.0) return;
      _feedScrollController.jumpTo(safeOffset);
    });
  }

  Future<void> _showReplyComposer({
    required String postId,
    required String postPreview,
  }) async {
    final content = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ReplyComposerRoute(
          title: 'Reply to post',
          previewText: postPreview,
          hintText: 'Write a reply...',
          actionLabel: 'Reply',
        ),
      ),
    );
    if (!mounted) return;
    final trimmed = (content ?? '').trim();
    if (trimmed.isEmpty) return;
    await _submitReply(postId: postId, content: trimmed);
  }

  Future<void> _showEditReplyComposer({
    required String postId,
    required String replyId,
    required String initialText,
  }) async {
    final content = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ReplyComposerRoute(
          title: 'Edit reply',
          hintText: 'Update your reply...',
          actionLabel: 'Save',
          initialText: initialText,
        ),
      ),
    );
    if (!mounted) return;
    final trimmed = (content ?? '').trim();
    if (trimmed.isEmpty) return;
    await _updateReply(
      postId: postId,
      replyId: replyId,
      content: trimmed,
    );
  }

  Future<void> _submitReply({
    required String postId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final userService = UserService();
    if (await userService.isCurrentlySuspended()) return;

    if (ProfanityService().hasProfanity(trimmed)) {
      final authUid = _currentAuthUid();
      final userId = _effectiveCurrentUserId();
      final publicName =
          await userService.ensureRecognizedPublicDisplayName() ??
          UserService.sanitizePublicDisplayName(userService.userName);
      await FirebaseFirestore.instance.collection('moderation_queue').add({
        'content': trimmed,
        'userId': userId,
        'authorUid': authUid,
        'userName': publicName,
        'source': 'Community Room Reply',
        'type': 'content_flag',
        'targetKind': 'community_reply',
        'metadata': {
          'postId': postId,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'reason': 'Profanity Detected',
        'status': 'pending',
      });
      return;
    }

    final authUid = _currentAuthUid();
    final userId = _effectiveCurrentUserId();
    final publicName = await userService.ensureRecognizedPublicDisplayName();
    if (userId.isEmpty || publicName == null) return;

    await _repliesCollection(postId).add({
      'content': trimmed,
      'userId': userId,
      'authorUid': authUid,
      'userName': publicName,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateReply({
    required String postId,
    required String replyId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    await _repliesCollection(postId).doc(replyId).update({
      'content': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteReply({
    required String postId,
    required String replyId,
  }) async {
    await _repliesCollection(postId).doc(replyId).delete();
  }

  Future<void> _toggleReplyLike({
    required String postId,
    required String replyId,
    required List<dynamic> likedBy,
  }) async {
    final authUid = _currentAuthUid().trim();
    final userServiceUid = UserService().userId.trim();
    final actorIds = <String>{
      if (authUid.isNotEmpty) authUid,
      if (userServiceUid.isNotEmpty) userServiceUid,
    };
    if (actorIds.isEmpty) return;

    final actorId = authUid.isNotEmpty ? authUid : userServiceUid;
    final likedBySet = likedBy
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final alreadyLiked = actorIds.any(likedBySet.contains);

    final replyRef = _repliesCollection(postId).doc(replyId);
    try {
      if (alreadyLiked) {
        await replyRef.update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove(actorIds.toList()),
        });
      } else {
        await replyRef.update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([actorId]),
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update reply like: $e')),
      );
    }
  }

  Future<void> _reportReply(String postId, String replyId, Map<String, dynamic> reply) async {
    final reporter = UserService();
    final reportedUserId = (
      reply['authorUid'] ??
      reply['userId'] ??
      reply['uid'] ??
      reply['authorId'] ??
      reply['senderId'] ??
      ''
    ).toString().trim();
    final content = (
      reply['content'] ??
      reply['text'] ??
      reply['message'] ??
      reply['body'] ??
      ''
    ).toString().trim();

    final authUid = _currentAuthUid().trim();
    final userServiceUid = reporter.userId.trim();
    final actorIds = <String>{
      if (authUid.isNotEmpty) authUid,
      if (userServiceUid.isNotEmpty) userServiceUid,
    };

    if (reportedUserId.isEmpty || actorIds.contains(reportedUserId)) {
      return;
    }

    final reportDetails = await _promptReportDetails(label: 'reply');
    if (reportDetails == null) return;

    try {
      await reporter.reportContent(
        reportedUserId,
        content,
        reportDetails['reason']!,
        'Community Room Reply',
        metadata: {
          'targetKind': 'community_reply',
          'targetId': replyId,
          'postId': postId,
          'replyId': replyId,
          'reportExplanation': reportDetails['explanation']!,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report sent to moderation.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not report reply: $e')),
      );
    }
  }

  Future<String> _resolveDisplayNameForPost(Map<String, dynamic> post) {
    final rawName =
        UserService.sanitizePublicDisplayName(post['userName']?.toString());
    final userId = (post['authorUid'] ?? post['userId'] ?? '').toString().trim();
    return _resolveDisplayNameForUser(userId, rawName);
  }

  String _initialDisplayNameForPost(Map<String, dynamic> post) {
    final candidates = [
      post['userName'],
      post['displayName'],
      post['name'],
      post['username'],
    ];
    for (final candidate in candidates) {
      final sanitized =
          UserService.sanitizePublicDisplayName(candidate?.toString());
      if (sanitized.isNotEmpty && sanitized.toLowerCase() != 'member') {
        return sanitized;
      }
    }
    return 'Member';
  }

  Future<String> _resolveDisplayNameForUser(String userId, String rawName) {
    final cleanRaw = UserService.sanitizePublicDisplayName(rawName);
    if (cleanRaw.isNotEmpty && cleanRaw.toLowerCase() != 'member') {
      return Future.value(cleanRaw);
    }
    if (userId.isEmpty) return Future.value('Member');
    final existing = _resolvedNameFutureByUserId[userId];
    if (existing != null) return existing;
    final future = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get()
        .then((doc) {
      final data = doc.data();
      final candidates = [
        data?['username'],
        data?['userName'],
        data?['displayName'],
        data?['name'],
      ];
      for (final candidate in candidates) {
        final sanitized = UserService.sanitizePublicDisplayName(candidate?.toString());
        if (sanitized.isNotEmpty && sanitized.toLowerCase() != 'member') {
          return sanitized;
        }
      }
      return 'Member';
    }).catchError((_) => 'Member');
    _resolvedNameFutureByUserId[userId] = future;
    return future;
  }

  Widget _buildMediaGallery(Map<String, dynamic> post) {
    final mediaUrls = _extractMediaUrls(post);
    if (mediaUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    final showGallery = mediaUrls.length > 1;
    final imageUrl = mediaUrls.first;
    final imageWidth = (post['imageWidth'] as num?)?.toDouble() ?? 0;
    final imageHeight = (post['imageHeight'] as num?)?.toDouble() ?? 0;
    final previewHeight = imageWidth > 0 && imageHeight > 0
        ? (imageHeight >= imageWidth
            ? (MediaQuery.of(context).size.height * 0.58).clamp(360.0, 640.0)
            : (MediaQuery.of(context).size.height * 0.42).clamp(280.0, 420.0))
        : (MediaQuery.of(context).size.height * 0.56).clamp(340.0, 600.0);

    if (!showGallery) {
      return GestureDetector(
        onTap: () => _showExpandedImage(imageUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.22),
            child: SizedBox(
              height: previewHeight,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Image could not be displayed.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: previewHeight,
          child: PageView.builder(
            itemCount: mediaUrls.length,
            itemBuilder: (context, index) {
              final url = mediaUrls[index];
              return GestureDetector(
                onTap: () => _showExpandedImage(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    color: Colors.black.withValues(alpha: 0.22),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Image could not be displayed.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(mediaUrls.length, (index) {
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            );
          }),
        ),
      ],
    );
  }

  Future<void> _showExpandedImage(String imageUrl) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasPendingImages) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Photos attached',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _clearPendingImage,
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  Text(
                    '$_pendingImageCount of $_maximumImagesPerPost selected • '
                    '${_remainingImageSlots()} more can be added to this post',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (_postingStatus != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _postingStatus!,
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                    ),
                  ],
                  if ((_usageService?.monthlyImageUploadLimit ?? 0) > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${((_usageService?.monthlyImageUploadLimit ?? 0) - _imageUploadsUsedThisMonth).clamp(0, _usageService?.monthlyImageUploadLimit ?? 0)} monthly image uploads remaining',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: (_pendingPickedImages.length + _pendingVaultImages.length),
                      itemBuilder: (context, index) {
                        if (index < _pendingPickedImages.length) {
                          final image = _pendingPickedImages[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 92,
                                    height: 120,
                                    child: FutureBuilder<Uint8List>(
                                      future: _previewBytesFor(image),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasData) {
                                          return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                        }
                                        return Container(
                                          color: Colors.black.withValues(alpha: 0.2),
                                          child: const Center(
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _removePendingImageAt(index),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final vaultIndex = index - _pendingPickedImages.length;
                        final item = _pendingVaultImages[vaultIndex];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 92,
                                  height: 120,
                                  child: Image.network(
                                    (item['downloadUrl'] ?? '').toString(),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removePendingImageAt(index),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (_pendingPickedImages.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: _saveCameraToVault,
                          onChanged: (value) {
                            if (!mounted) return;
                            setState(() => _saveCameraToVault = value ?? false);
                          },
                          activeColor: Colors.amber,
                          checkColor: Colors.black,
                        ),
                        const Expanded(
                          child: Text(
                            'Save selected images to My Harmony Vault as well',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if ((_pendingPickedImages.length + _pendingVaultImages.length) > 1) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Remove any image before posting, or clear all selections.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('app_config')
                .doc('community_support')
                .snapshots(),
            builder: (context, supportSnapshot) {
              final supportConfig =
                  supportSnapshot.data?.data() as Map<String, dynamic>? ?? {};
              if (supportConfig['isSupportFeatureEnabled'] != true) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: CheckboxListTile(
                  value: _isSupportRequest,
                  onChanged: (value) =>
                      setState(() => _isSupportRequest = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: Colors.amber,
                  title: const Text(
                    'Request Community Support',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _postController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Message...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _isLoadingImageUsage
                    ? 'Checking image uploads...'
                    : ((_usageService?.monthlyImageUploadLimit ?? 0) > 0
                        ? '${((_usageService?.monthlyImageUploadLimit ?? 0) - _imageUploadsUsedThisMonth).clamp(0, _usageService?.monthlyImageUploadLimit ?? 0)} image uploads left'
                        : 'Attach image'),
                onPressed: _isPosting ? null : _openImagePickerSheet,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
                    if ((_usageService?.monthlyImageUploadLimit ?? 0) > 0)
                      Positioned(
                        right: -8,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black87, width: 0.8),
                          ),
                          child: Text(
                            _isLoadingImageUsage
                                ? '...'
                                : '${((_usageService?.monthlyImageUploadLimit ?? 0) - _imageUploadsUsedThisMonth).clamp(0, _usageService?.monthlyImageUploadLimit ?? 0)}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _messagesRemaining <= 3
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _messagesRemaining <= 3
                        ? Colors.red.withValues(alpha: 0.5)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 14,
                      color: _messagesRemaining <= 3 ? Colors.redAccent : Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_messagesRemaining/$_dailyLimit',
                      style: TextStyle(
                        color: _messagesRemaining <= 3
                            ? Colors.redAccent
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _isPosting ? null : _submitPost,
                icon: _isPosting
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                          semanticsLabel: _postingStatus ?? 'Sharing post',
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.amber),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveCounterTop = widget.showAppBar ? 40.0 : -44.0;
    final translateTop = widget.showAppBar ? 22.0 : -50.0;
    return GradientScaffold(
      appBar: widget.showAppBar
          ? AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: 0,
            elevation: 0,
            backgroundColor: Colors.transparent,
            )
          : null,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.showAppBar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
                  child: Row(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: TranslationService.instance.enabledNotifier,
                        builder: (context, enabled, _) {
                          return SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                              visualDensity: VisualDensity.compact,
                              tooltip: enabled
                                  ? 'Disable Translation'
                                  : 'Enable Translation',
                              onPressed: () => unawaited(_toggleTranslation()),
                              icon: Icon(
                                Icons.translate,
                                size: 20,
                                color: enabled ? Colors.greenAccent : Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      IgnorePointer(
                        ignoring: true,
                        child: Transform.scale(
                          scale: 0.94,
                          alignment: Alignment.centerLeft,
                          child: const LiveRoomCounterBadge(
                            roomId: 'community_room',
                            enabled: true,
                            showBackground: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Common Room',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<HomeSpeakerUiState>(
                        valueListenable: homeSpeakerUiStateNotifier,
                        builder: (context, speakerState, _) {
                          final toggle = homeSpeakerToggleCallback;
                          if (!speakerState.visible || toggle == null) {
                            return const SizedBox(width: 36, height: 36);
                          }
                          return IconButton(
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            tooltip: speakerState.muted
                                ? 'Enable background audio'
                                : 'Mute background audio',
                            onPressed: () => unawaited(toggle()),
                            icon: Icon(
                              speakerState.muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: speakerState.muted ? Colors.white70 : Colors.amberAccent,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Column(
            children: [
          if (widget.showAppBar)
            const SizedBox(height: 76),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('app_config')
                .doc('community_settings')
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data() ?? const <String, dynamic>{};
              final showPinned = (data['showPinnedAdminMessage'] as bool?) ?? true;
              final adminMessage = (data['admin_message'] as String?)?.trim() ?? '';
              if (!showPinned || adminMessage.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                padding: const EdgeInsets.all(14),
                decoration: _panelDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.push_pin, color: Colors.amber, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Pinned',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TranslatableText(
                      adminMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      enableLinks: true,
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _communityPostsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No posts yet. Be the first!',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                final posts = snapshot.data!.docs;
                _scrollToAndHighlightPendingTarget(posts);
                return ListView.builder(
                  controller: _feedScrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final postDoc = posts[index];
                    final post = postDoc.data();
                    final postId = postDoc.id;
                    final imageUrl = (post['imageUrl'] ?? '').toString();
                    final hasImage = (post['hasImage'] ?? false) == true && imageUrl.isNotEmpty;
                    final ts = (post['timestamp'] as Timestamp?)?.toDate();
                    final likedBy = List<dynamic>.from(post['likedBy'] ?? const []);
                    final isOwnPost = _isPostOwnedByCurrentUser(post);
                    final repliesExpanded = _expandedReplyPostIds.contains(postId);

                    return FutureBuilder<String>(
                      future: _resolveDisplayNameForPost(post),
                      initialData: _initialDisplayNameForPost(post),
                      builder: (context, nameSnapshot) {
                        final displayName = nameSnapshot.data ?? 'Member';
                        final isHighlighted = _highlightedPostId == postId;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: isHighlighted
                              ? _panelDecoration().copyWith(
                                  border: Border.all(color: Colors.amberAccent, width: 2),
                                )
                              : _panelDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.white12,
                                    backgroundImage: post['userPhoto'] != null
                                        ? NetworkImage(post['userPhoto'])
                                        : null,
                                    child: post['userPhoto'] == null
                                        ? Text(
                                            displayName.isNotEmpty
                                                ? displayName[0].toUpperCase()
                                                : 'M',
                                            style: const TextStyle(color: Colors.white),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  if (ts != null)
                                    Text(
                                      DateFormat('MMM d, h:mm a').format(ts),
                                      style: const TextStyle(color: Colors.white54),
                                    ),
                                ],
                              ),
                              if (((post['content'] ?? '') as String).trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                TranslatableText(
                                  (post['content'] ?? '').toString(),
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  enableLinks: true,
                                ),
                              ],
                              if (hasImage) ...[
                                const SizedBox(height: 12),
                                _buildMediaGallery(post),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  GestureDetector(
                                    onTap: () => _toggleLike(postId, likedBy),
                                    child: Row(
                                      children: [
                                        Icon(
                                          likedBy.contains(_effectiveCurrentUserId())
                                              ? Icons.thumb_up
                                              : Icons.thumb_up_outlined,
                                          size: 16,
                                          color: likedBy.contains(_effectiveCurrentUserId())
                                              ? Colors.greenAccent
                                              : Colors.white54,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${post['likes'] ?? 0}',
                                          style: const TextStyle(color: Colors.white54),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isOwnPost) ...[
                                    const SizedBox(width: 10),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, color: Colors.white54),
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          await _showEditPostComposer(
                                            postId: postId,
                                            initialText: (post['content'] ?? '').toString(),
                                            hasImage: hasImage,
                                          );
                                        } else if (value == 'remove_image') {
                                          await _removePostImage(postId: postId, post: post);
                                        } else if (value == 'delete') {
                                          await _confirmAndDeletePost(postId);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem<String>(
                                          value: 'edit',
                                          child: Text('Edit post'),
                                        ),
                                        if (hasImage)
                                          const PopupMenuItem<String>(
                                            value: 'remove_image',
                                            child: Text('Remove image'),
                                          ),
                                        const PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Text('Delete post'),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    const SizedBox(width: 10),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.flag_outlined, color: Colors.white54),
                                      onSelected: (value) async {
                                        if (value == 'report') {
                                          await _reportPost(postId, post);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem<String>(
                                          value: 'report',
                                          child: Text('Report user'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              ThreadedRepliesPanel(
                                postId: postId,
                                isExpanded: repliesExpanded,
                                currentUserId: _effectiveCurrentUserId(),
                                currentAuthUid: _currentAuthUid(),
                                repliesStream: _repliesCollection(postId)
                                    .orderBy('timestamp', descending: false)
                                    .snapshots(),
                                resolveDisplayName: _resolveDisplayNameForUser,
                                onToggleExpanded: () => _toggleRepliesExpanded(postId),
                                onComposeReply: () => _showReplyComposer(
                                  postId: postId,
                                  postPreview: (post['content'] ?? '').toString(),
                                ),
                                onEditReply: (replyId, reply) => _showEditReplyComposer(
                                  postId: postId,
                                  replyId: replyId,
                                  initialText: (reply['content'] ?? '').toString(),
                                ),
                                onDeleteReply: (replyId, reply) => _deleteReply(
                                  postId: postId,
                                  replyId: replyId,
                                ),
                                onLikeReply: (replyId, reply) => _toggleReplyLike(
                                  postId: postId,
                                  replyId: replyId,
                                  likedBy: List<dynamic>.from(reply['likedBy'] ?? const []),
                                ),
                                onReportReply: (replyId, reply) => _reportReply(
                                  postId,
                                  replyId,
                                  reply,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          _buildComposer(),
            ],
          ),
          if (!widget.showAppBar)
            Positioned(
              top: liveCounterTop,
              left: 66,
              child: IgnorePointer(
                ignoring: true,
                child: Transform.translate(
                  offset: const Offset(0, 2),
                  child: Transform.scale(
                    scale: 0.94,
                    alignment: Alignment.topLeft,
                    child: const LiveRoomCounterBadge(
                      roomId: 'community_room',
                      enabled: true,
                      showBackground: false,
                    ),
                  ),
                ),
              ),
            ),
          if (!widget.showAppBar)
            Positioned(
              top: translateTop,
              left: -6,
              child: Transform.translate(
                offset: const Offset(0, -28),
                child: _buildTranslateToggle(hitSize: 96, iconSize: 20),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReplyComposerRoute extends StatefulWidget {
  final String title;
  final String? previewText;
  final String hintText;
  final String actionLabel;
  final String initialText;

  const _ReplyComposerRoute({
    required this.title,
    this.previewText,
    required this.hintText,
    required this.actionLabel,
    this.initialText = '',
  });

  @override
  State<_ReplyComposerRoute> createState() => _ReplyComposerRouteState();
}

class _ReplyComposerRouteState extends State<_ReplyComposerRoute> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((widget.previewText ?? '').trim().isNotEmpty) ...[
                Text(
                  widget.previewText!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(_controller.text);
                      },
                      child: Text(widget.actionLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}