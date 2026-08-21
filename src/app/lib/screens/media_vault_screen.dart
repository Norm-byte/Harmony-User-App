import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../services/media_vault_service.dart';
import '../services/user_service.dart';
import '../widgets/gradient_scaffold.dart';
import 'community_feed_screen.dart';

class MediaVaultScreen extends StatefulWidget {
  const MediaVaultScreen({super.key});

  @override
  State<MediaVaultScreen> createState() => _MediaVaultScreenState();
}

class _MediaVaultScreenState extends State<MediaVaultScreen> {
  final MediaVaultService _mediaVaultService = MediaVaultService();
  bool _isDeleting = false;

  bool _isPermissionDeniedError(Object error) {
    if (error is FirebaseException) {
      return error.code.toLowerCase() == 'permission-denied';
    }
    final message = error.toString().toLowerCase();
    return message.contains('permission-denied') ||
        (message.contains('permission') && message.contains('denied'));
  }

  String _effectiveUid(UserService user) {
    final fromUser = user.userId.trim();
    if (fromUser.isNotEmpty) return fromUser;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  Future<void> _deleteImage({
    required String uid,
    required String imageId,
    required String storagePath,
  }) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete vault image?'),
            content: const Text(
              'This will remove the image from your My Harmony Vault.',
            ),
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
        ) ??
        false;

    if (!confirmed) return;

    if (!mounted) return;
    setState(() => _isDeleting = true);
    try {
      await _mediaVaultService.deleteVaultImage(
        uid: uid,
        imageId: imageId,
        storagePath: storagePath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image removed from vault.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  void _useInCommonRoom(Map<String, dynamic> image) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityFeedScreen(preselectedVaultImage: image),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserService>(
      builder: (context, user, _) {
        final uid = _effectiveUid(user);

        return GradientScaffold(
          appBar: AppBar(
            title: const Text('My Harmony Vault'),
            foregroundColor: Colors.white,
          ),
          body: uid.isEmpty
              ? const Center(
                  child: Text(
                    'Could not resolve account id. Please re-login and try again.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        'Store your photos here, remove old ones, or open one directly in Common Room.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _mediaVaultService.watchVaultImages(uid),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            final denied = _isPermissionDeniedError(snapshot.error!);
                            return Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    denied
                                        ? 'Vault access is currently restricted for this account.'
                                        : 'Could not load vault images right now.',
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    denied
                                        ? 'You can still attach images from Common Room while this is being fixed.'
                                        : 'Details: ${snapshot.error}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          }

                          if (snapshot.connectionState == ConnectionState.waiting &&
                              !snapshot.hasData) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: Colors.white),
                                  SizedBox(height: 12),
                                  Text(
                                    'Loading vault images...',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (!snapshot.hasData) {
                            return const Center(
                              child: Text(
                                'Vault is temporarily unavailable. Please try again.',
                                style: TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          final docs = snapshot.data!.docs;
                          final activeDocs = docs.where((doc) {
                            final data = doc.data();
                            final status = (data['status'] ?? 'active').toString();
                            final url = (data['downloadUrl'] ?? '').toString();
                            return status == 'active' && url.isNotEmpty;
                          }).toList();

                          if (activeDocs.isEmpty) {
                            return const Center(
                              child: Text(
                                'No vault images yet. Add one from Common Room.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            );
                          }

                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.78,
                                ),
                            itemCount: activeDocs.length,
                            itemBuilder: (context, index) {
                              final doc = activeDocs[index];
                              final data = doc.data();
                              final imageId = doc.id;
                              final url = (data['downloadUrl'] ?? '').toString();
                              final storagePath =
                                  (data['storagePath'] ?? '').toString();
                              final width = (data['width'] as num?)?.toInt() ?? 0;
                              final height = (data['height'] as num?)?.toInt() ?? 0;
                              final bytes = (data['bytes'] as num?)?.toInt() ?? 0;

                              final imagePayload = <String, dynamic>{
                                'imageId': imageId,
                                'downloadUrl': url,
                                'storagePath': storagePath,
                                'width': width,
                                'height': height,
                                'bytes': bytes,
                              };

                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(12),
                                        ),
                                        child: Image.network(url, fit: BoxFit.cover),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        '${width}x$height • ${(bytes / 1024).round()}KB',
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextButton.icon(
                                            onPressed: () => _useInCommonRoom(imagePayload),
                                            icon: const Icon(
                                              Icons.chat_bubble_outline,
                                              size: 16,
                                            ),
                                            label: const Text('Use'),
                                          ),
                                        ),
                                        Expanded(
                                          child: IconButton(
                                            tooltip: 'Delete',
                                            onPressed: _isDeleting
                                                ? null
                                                : () => _deleteImage(
                                                    uid: uid,
                                                    imageId: imageId,
                                                    storagePath: storagePath,
                                                  ),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 20,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
