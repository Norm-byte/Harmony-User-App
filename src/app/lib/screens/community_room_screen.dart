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
  final TextEditingController _postController = TextEditingController();
  final ScrollController _feedScrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final MediaVaultService _mediaVaultService = MediaVaultService();
  final Map<String, Future<String>> _resolvedNameFutureByUserId = {};
  final Set<String> _expandedReplyPostIds = {};
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _communityPostsStream;

  UsageService? _usageService;
  XFile? _pendingPickedImage;
  Map<String, dynamic>? _pendingVaultImage;
  Uint8List? _pendingPreviewBytes;
  bool _saveCameraToVault = true;
  bool _isPosting = false;
  bool _isLoadingImageUsage = false;
  int _messagesRemaining = 0;
  int _dailyLimit = 5;
  int _imageUploadsUsedThisMonth = 0;

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
      _pendingVaultImage = Map<String, dynamic>.from(
        widget.preselectedVaultImage!,
      );
    }
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
        if (!mounted) return false;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Monthly Image Limit Reached'),
            content: const Text(
              'You have used your monthly photo upload limit. Upgrade your tier for more uploads.',
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

  void _clearPendingImage() {
    if (!mounted) return;
    setState(() {
      _pendingPickedImage = null;
      _pendingVaultImage = null;
      _pendingPreviewBytes = null;
      _saveCameraToVault = true;
    });
  }

  Future<void> _pickFromCamera() async {
    final userId = _requireCurrentUserId();
    if (userId == null || !await _canUploadMoreImages(userId)) return;
    final picked = await _imagePicker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final preview = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingPickedImage = picked;
      _pendingVaultImage = null;
      _pendingPreviewBytes = preview;
      _saveCameraToVault = true;
    });
  }

  Future<void> _pickFromGallery() async {
    final userId = _requireCurrentUserId();
    if (userId == null || !await _canUploadMoreImages(userId)) return;
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final preview = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingPickedImage = picked;
      _pendingVaultImage = null;
      _pendingPreviewBytes = preview;
      _saveCameraToVault = false;
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
                        setState(() {
                          _pendingVaultImage = {
                            'imageId': doc.id,
                            'downloadUrl': url,
                            'storagePath': (data['storagePath'] ?? '').toString(),
                            'bytes': (data['bytes'] as num?)?.toInt() ?? 0,
                            'width': (data['width'] as num?)?.toInt() ?? 0,
                            'height': (data['height'] as num?)?.toInt() ?? 0,
                          };
                          _pendingPickedImage = null;
                          _pendingPreviewBytes = null;
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
        title: const Text('Attach Image'),
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
    final hasPendingImage = _pendingPickedImage != null || _pendingVaultImage != null;
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

    setState(() => _isPosting = true);

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
      };

      if (_pendingVaultImage != null) {
        final expiryDays = (_usageService?.feedImageExpiryDays ?? 5).clamp(1, 90);
        postData.addAll({
          'hasImage': true,
          'imageUrl': _pendingVaultImage!['downloadUrl'],
          'imageStoragePath': _pendingVaultImage!['storagePath'],
          'imageBytes': _pendingVaultImage!['bytes'],
          'imageWidth': _pendingVaultImage!['width'],
          'imageHeight': _pendingVaultImage!['height'],
          'imageCreatedAt': FieldValue.serverTimestamp(),
          'imageExpiresAt': Timestamp.fromDate(
            DateTime.now().add(Duration(days: expiryDays)),
          ),
          'imageStatus': 'active',
          'imageSource': 'vault',
        });
      } else if (_pendingPickedImage != null) {
        if (!await _canUploadMoreImages(userId)) return;
        final prepared = await _mediaVaultService.prepareImage(_pendingPickedImage!);
        final roomUpload = await _mediaVaultService.uploadToRoom(
          roomId: 'community_room',
          uid: userId,
          prepared: prepared,
        );

        final expiryDays = (_usageService?.feedImageExpiryDays ?? 5).clamp(1, 90);
        postData.addAll({
          'hasImage': true,
          'imageUrl': roomUpload.downloadUrl,
          'imageStoragePath': roomUpload.storagePath,
          'imageBytes': roomUpload.bytes,
          'imageWidth': roomUpload.width,
          'imageHeight': roomUpload.height,
          'imageCreatedAt': FieldValue.serverTimestamp(),
          'imageExpiresAt': Timestamp.fromDate(
            DateTime.now().add(Duration(days: expiryDays)),
          ),
          'imageStatus': 'active',
          'imageSource': 'upload',
        });

        await _mediaVaultService.incrementSharedRoomUploadsForMonth(
          userId,
          DateTime.now(),
        );

        if (_saveCameraToVault) {
          await _mediaVaultService.uploadToVault(
            uid: userId,
            prepared: prepared,
            source: 'camera_auto_save',
          );
          await _mediaVaultService.incrementVaultUploadsForMonth(
            userId,
            DateTime.now(),
          );
        }

        unawaited(_refreshImageUsageCounter());
      }

      await FirebaseFirestore.instance.collection('community_posts').add(postData);
      await _decrementMessageLimit();
      _postController.clear();
      _clearPendingImage();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post shared with the community!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error posting: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
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

  Future<void> _reportPost(Map<String, dynamic> post) async {
    final reporter = UserService();
    final reportedUserId = (post['userId'] ?? '').toString().trim();
    final content = (post['content'] ?? '').toString().trim();
    if (reportedUserId.isEmpty || reportedUserId == reporter.userId.trim()) {
      return;
    }
    await reporter.reportContent(
      reportedUserId,
      content,
      'User Reported',
      'Community Room',
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

    try {
      await reporter.reportContent(
        reportedUserId,
        content,
        'User Reported',
        'Community Room Reply',
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

  double _imagePreviewHeight(BuildContext context, Map<String, dynamic> post) {
    final screenHeight = MediaQuery.of(context).size.height;
    final width = (post['imageWidth'] as num?)?.toDouble() ?? 0;
    final height = (post['imageHeight'] as num?)?.toDouble() ?? 0;
    if (width > 0 && height > 0) {
      if (height >= width) {
        return (screenHeight * 0.58).clamp(360.0, 640.0);
      }
      return (screenHeight * 0.42).clamp(280.0, 420.0);
    }
    return (screenHeight * 0.56).clamp(340.0, 600.0);
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
          if (_pendingPreviewBytes != null || _pendingVaultImage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 88,
                      height: 132,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.2),
                        child: _pendingPreviewBytes != null
                            ? Image.memory(_pendingPreviewBytes!, fit: BoxFit.contain)
                            : Image.network(
                                (_pendingVaultImage?['downloadUrl'] ?? '').toString(),
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Photo attached',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _pendingVaultImage != null
                              ? 'Using image from My Harmony Vault'
                              : 'Using new image from this device',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _clearPendingImage,
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (_pendingPickedImage != null) ...[
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
                      'Save this image to My Harmony Vault as well',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
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
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
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
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: _panelDecoration(),
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
                                GestureDetector(
                                  onTap: () => _showExpandedImage(imageUrl),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      width: double.infinity,
                                      color: Colors.black.withValues(alpha: 0.22),
                                      child: SizedBox(
                                        height: _imagePreviewHeight(context, post),
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
                                ),
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
                                          await _reportPost(post);
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