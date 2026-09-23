import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import '../services/favorites_service.dart';
import '../services/group_service.dart';
import '../services/event_service.dart';
import '../services/user_service.dart';
import '../services/subscription_service.dart';
import 'category_favorites_screen.dart';
import 'chat_screen.dart';
import 'community_groups_screen.dart';
import 'legal_document_screen.dart';
import 'personal_information_screen.dart';
import 'media_vault_screen.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';
import '../widgets/support_icon.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<int> _totalUsersFuture;
  late Future<int> _timeZoneUsersFuture;
  String _pastIntentFilter = '';
  String _supportIntentFilter = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _totalUsersFuture = _fetchWorldwideUserTotal();
    _timeZoneUsersFuture = _fetchRegionalUserTotal();
  }

  DateTime? _registeredEventDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool _isPastRegisteredEvent(Map<String, dynamic> event, DateTime now) {
    final end = _registeredEventDate(event['endTime']) ??
        _registeredEventDate(event['startTime'] ?? event['timestamp'])?.add(
          const Duration(hours: 1),
        );
    if (end == null) return false;
    final visibilityAfter = (event['visibilityAfterMinutes'] as num?)?.toInt() ?? 0;
    return end.add(Duration(minutes: visibilityAfter)).isBefore(now);
  }

  Future<void> _editPastIntent(Map<String, dynamic> event) async {
    final eventId = (event['registeredEventId'] ?? '').toString().trim();
    final userId = UserService().userId.trim();
    if (eventId.isEmpty || userId.isEmpty) return;

    final controller = TextEditingController(
      text: (event['intent'] ?? '').toString(),
    );
    final updatedIntent = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Past Intent'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Your personal intention',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updatedIntent == null || updatedIntent.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('registered_events')
        .doc(eventId)
        .update({
      'intent': updatedIntent,
      'intentEditedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deletePastIntent(Map<String, dynamic> event) async {
    final eventId = (event['registeredEventId'] ?? '').toString().trim();
    final userId = UserService().userId.trim();
    if (eventId.isEmpty || userId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete past intent?'),
        content: const Text('This removes the reflection from your My Harmony history.'),
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
    if (confirmed != true) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('registered_events')
        .doc(eventId)
        .delete();
  }

  Widget _buildSupportIntentsSection() {
    final uid = UserService().userId;
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('support_intents')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final normalizedFilter = _supportIntentFilter.trim().toLowerCase();
        final visibleDocs = normalizedFilter.isEmpty
            ? docs
            : docs.where((doc) {
                final content = (doc.data()['content'] as String?)?.toLowerCase() ?? '';
                return content.contains(normalizedFilter);
              }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'My Support Requests',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${docs.length})',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (normalizedFilter.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${visibleDocs.length} match${visibleDocs.length == 1 ? '' : 'es'}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                    ),
                  ),
                IconButton(
                  tooltip: normalizedFilter.isEmpty ? 'Filter support requests' : 'Change filter',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    normalizedFilter.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt,
                    color: normalizedFilter.isEmpty ? Colors.white70 : Colors.amberAccent,
                    size: 20,
                  ),
                  onPressed: () async {
                    final controller = TextEditingController(text: _supportIntentFilter);
                    final filter = await showDialog<String>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Filter Support Requests'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: 'Search a word or phrase'),
                          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(''),
                            child: const Text('Clear'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    );
                    controller.dispose();
                    if (filter != null && mounted) {
                      setState(() => _supportIntentFilter = filter);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'A permanent record of requests you have posted, even after they leave the public feed.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (visibleDocs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  docs.isEmpty
                      ? 'Requests you post with "Request Community Support" will appear here.'
                      : 'No support requests match this filter.',
                  style: const TextStyle(color: Colors.white54),
                ),
              )
            else
              // Fixed-height, independently-scrollable box. This is safe here
              // because the outer container is now SingleChildScrollView, not
              // ListView - a ListView-inside-ListView is what caused the lock;
              // ListView-inside-SingleChildScrollView is a stable, common
              // Flutter pattern.
              SizedBox(
                height: 264,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: visibleDocs.length,
                  itemBuilder: (context, index) => _buildSupportIntentCard(visibleDocs[index]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSupportIntentCard(QueryDocumentSnapshot<Map<String, dynamic>> intentDoc) {
    final intent = intentDoc.data();
    final postId = (intent['postId'] as String?) ?? '';
    final isRealized = intent['isRealized'] == true;
    final createdAt = (intent['createdAt'] as Timestamp?)?.toDate();
    final dateLabel = createdAt == null ? '' : DateFormat('MMM d, yyyy, h:mm a').format(createdAt);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: postId.isEmpty
          ? null
          : FirebaseFirestore.instance.collection('community_posts').doc(postId).snapshots(),
      builder: (context, liveSnap) {
        // Prefer the live post while it still exists (single source of truth);
        // fall back to the permanent snapshot once it's gone (deleted/expired).
        final livePost = liveSnap.data?.data();
        final isLive = livePost != null;
        final content = (isLive ? livePost['content'] : intent['content']) as String? ?? '';
        final imageUrl = isLive
            ? ((livePost['hasImage'] == true) ? livePost['imageUrl'] as String? : null)
            : intent['imageUrl'] as String?;
        final likes = isLive ? ((livePost['likes'] as num?)?.toInt() ?? 0) : 0;
        final supportCount = isLive ? ((livePost['supportTapCount'] as num?)?.toInt() ?? 0) : 0;

        void showExpanded() {
          showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
              title: const Text('My Support Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (imageUrl != null && imageUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(imageUrl, fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(content, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
                    const SizedBox(height: 12),
                    if (dateLabel.isNotEmpty)
                      Text(dateLabel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    if (isLive)
                      Row(
                        children: [
                          const Icon(Icons.thumb_up, size: 14, color: Colors.greenAccent),
                          const SizedBox(width: 4),
                          Text('$likes', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          const SizedBox(width: 12),
                          const Icon(Icons.front_hand, size: 14, color: Colors.amberAccent),
                          const SizedBox(width: 4),
                          Text('$supportCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      )
                    else
                      const Text(
                        'This request is no longer on the public feed, but your record is kept here.',
                        style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close', style: TextStyle(color: Colors.amberAccent)),
                ),
              ],
            ),
          );
        }

        Future<void> editIntent() async {
          final controller = TextEditingController(text: content);
          final result = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Edit support request'),
              content: TextField(controller: controller, maxLines: 4, autofocus: true),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (result == null || result.isEmpty) return;
          if (isLive) {
            await FirebaseFirestore.instance.collection('community_posts').doc(postId).update({
              'content': result,
              'editedAt': FieldValue.serverTimestamp(),
            });
          }
          await intentDoc.reference.update({'content': result});
        }

        Future<void> deleteIntent() async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Delete this request?'),
              content: Text(isLive
                  ? 'This removes it from Common Room, Community Support, and this list.'
                  : 'This removes it from your Past Intents list.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
              ],
            ),
          );
          if (confirmed != true) return;
          if (isLive) {
            await FirebaseFirestore.instance.collection('community_posts').doc(postId).delete();
          }
          await intentDoc.reference.delete();
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: showExpanded, // always tappable, even a short/no-text request
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Icon(
                  isRealized ? Icons.check_circle : Icons.front_hand,
                  color: isRealized ? Colors.greenAccent : Colors.amberAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        content.isEmpty ? 'Request unavailable' : content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLive ? '$dateLabel • Support taps: $supportCount' : '$dateLabel • Removed from feed',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: isRealized ? 'Mark as not yet realized' : 'Mark as realized/healed',
                  onPressed: () => intentDoc.reference.update({'isRealized': !isRealized}),
                  icon: Icon(
                    isRealized ? Icons.check_circle : Icons.check_circle_outline,
                    color: isRealized ? Colors.greenAccent : Colors.white70,
                    size: 19,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: editIntent,
                  icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 19),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: deleteIntent,
                  icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 19),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: "My Profile"),
            Tab(text: "Settings"),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // 1. My Profile Tab (User Experience)
              // SingleChildScrollView+Column, not ListView: this tab has many
              // independent StreamBuilders, and ListView's continuous extent
              // recalculation is what caused the scroll-to-bottom lock -
              // measuring the whole page as one Column avoids that entirely.
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                children: [
                   // Profile Header
                   const Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white24,
                            child: Icon(Icons.person, size: 50, color: Colors.white),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'My Harmony',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                   ),
                   const SizedBox(height: 32),

                   // Social Stats (My Impact)
                   Consumer<EventService>(
                     builder: (context, eventService, _) {
                       final userId = UserService().userId;
                       return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                         stream: userId.isEmpty
                             ? null
                             : FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
                         builder: (context, userSnapshot) {
                           final thumbprintCount =
                               (userSnapshot.data?.data()?['thumbprintTapCount'] as num?)?.toInt() ?? 0;
                           return Card(
                          elevation: 4,
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'My Impact',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatItem('Intents Added', '${eventService.myEvents.length}'),
                                    _buildStatItem('Thumbprints Tapped', '$thumbprintCount'),
                                    _buildTimeZoneUsersStatItem(),
                                    _buildTotalUsersStatItem(),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Divider(color: Colors.white24),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildLikesReceivedStatItem(),
                                    _buildMyCommentsCountStatItem(),
                                    _buildSupportReceivedStatItem(),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildMostLikedCommentCard(),
                                  const SizedBox(height: 12),
                                  _buildCommunityPulseCard(),
                                  const SizedBox(height: 12),
                                  _buildMostSupportedRequestCard(),
                                  const SizedBox(height: 16),

                              ],
                            ),
                          ),
                           );
                         },
                       );
                     }
                   ),
                    const SizedBox(height: 24),

                   // My Groups (Conditional)
                   StreamBuilder<DocumentSnapshot>(
                     stream: FirebaseFirestore.instance.collection('system_settings').doc('app_config').snapshots(),
                     builder: (context, configSnapshot) {
                       bool showChatRooms = true;
                       if (configSnapshot.hasData && configSnapshot.data!.exists) {
                          final data = configSnapshot.data!.data() as Map<String, dynamic>;
                          showChatRooms = data['show_niche_chat_rooms'] ?? true;
                       }

                       if (!showChatRooms) return const SizedBox.shrink();

                       return Consumer<GroupService>(
                      builder: (context, groupService, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('My Chat Rooms', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 12),
                            if (groupService.myGroups.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text("You haven't joined any chat rooms yet.", style: TextStyle(color: Colors.white54)),
                              )
                            else
                              SizedBox(
                                height: 110, // Increased height
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: groupService.myGroups.length,
                                  itemBuilder: (context, index) {
                                    final group = groupService.myGroups[index];
                                    final name = group['name'];
                                    final icon = group['iconCode'] != null
                                        ? IconData(group['iconCode'], fontFamily: 'MaterialIcons')
                                        : Icons.forum;
                                    final color = group['colorValue'] != null
                                        ? Color(group['colorValue'])
                                        : Colors.blue;

                                    return Stack(
                                      children: [
                                          GestureDetector(
                                            onTap: () {
                                              if (group['id'] != null) {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => ChatScreen(
                                                        eventTitle: name,
                                                        groupId: group['id'],
                                                      ),
                                                    ),
                                                  );
                                              }
                                            },
                                            child: Container(
                                              width: 140, 
                                              margin: const EdgeInsets.only(right: 12, top: 8), // Add top margin for delete button space if needed
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.white12),
                                              ),
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor: color.withValues(alpha: 0.2),
                                                    child: Icon(icon, color: color, size: 18),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          name,
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 0,
                                            right: 4,
                                            child: InkWell(
                                              onTap: () {
                                                 // Call leave group
                                                 if (group['id'] != null) {
                                                    groupService.leaveGroupById(group['id']);
                                                 }
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    );
                     }),
                    const SizedBox(height: 24),

                    // My Events (Scrollable Cards)
                    Consumer2<EventService, UserService>(
                      builder: (context, eventService, userService, _) {
                        final now = DateTime.now();

                        // 1. Start with confirmed events from Database
                        List<Map<String, dynamic>> combinedEvents = List.from(eventService.myEvents);

                        // 2. "Assumptive" Logic: Inject Worldwide Events if Auto-Join is ON
                        if (userService.autoJoinWorldwide) {
                           for (final event in eventService.events) {
                              if (event.type == EventType.global) {
                                  // FIX: Only consider it "Present" if there is a LIVE/FUTURE entry.
                                  // If the entry found is expired, we should ignore it and inject the new one.
                                  bool validEntryExists = combinedEvents.any((m) {
                                      if (m['eventId'] != event.id) {
                                        return false;
                                      }
                                      
                                      // Check expiration of this specific history item
                                      dynamic rawEnd = m['endTime'];
                                      DateTime? end;
                                      if (rawEnd is Timestamp) {
                                        end = rawEnd.toDate();
                                      } else if (rawEnd is DateTime) {
                                        end = rawEnd;
                                      } else if (rawEnd is String) {
                                        end = DateTime.tryParse(rawEnd);
                                      }
                                      
                                      // Fallback for End Time
                                      if (end == null) {
                                          dynamic rawStart = m['startTime'] ?? m['timestamp'];
                                          DateTime? start;
                                          if (rawStart is Timestamp) {
                                            start = rawStart.toDate();
                                          } else if (rawStart is DateTime) {
                                            start = rawStart;
                                          } else if (rawStart is String) {
                                            start = DateTime.tryParse(rawStart);
                                          }
                                          
                                          if (start != null) {
                                              end = start.add(const Duration(hours: 1));
                                          }
                                      }

                                      if (end != null) {
                                           // Check visibility window
                                           int visibilityAfter = m['visibilityAfterMinutes'] ?? 0;
                                           final expirationTime = end.add(Duration(minutes: visibilityAfter));
                                           
                                           // If this history item is still visible/active, we accept it as "Present".
                                           if (expirationTime.isAfter(now)) {
                                               return true;
                                           }
                                           return false; // It's expired history, ignore it
                                      }
                                      
                                      return true; // If we can't determine, assume present to avoid dupes
                                  });

                                  if (!validEntryExists) {
                                      combinedEvents.add({
                                        'eventId': event.id,
                                        'eventTitle': event.title,
                                        'intent': event.mostPopularIntent ?? 'Harmony',
                                        'startTime': event.startTime,
                                        'endTime': event.endTime,
                                        'visibilityAfterMinutes': event.visibilityAfterMinutes ?? 0,
                                        'isVirtual': true,
                                      });
                                  }
                              }
                           }
                        }

                        final activeEvents = combinedEvents.where((e) {
                           // Robust Timestamp handling
                           dynamic rawEnd = e['endTime'];
                           DateTime? end;
                           if (rawEnd is Timestamp) {
                             end = rawEnd.toDate();
                           } else if (rawEnd is DateTime) {
                             end = rawEnd; // Handle optimistic updates
                           } else if (rawEnd is String) {
                             end = DateTime.tryParse(rawEnd); // Fallback
                           }

                           // Robust StartTime handling to catch missing EndTime
                           dynamic rawStart = e['startTime'] ?? e['timestamp'];
                           DateTime? start;
                           if (rawStart is Timestamp) {
                             start = rawStart.toDate().toUtc(); // Normalize to UTC
                           } else if (rawStart is DateTime) {
                             start = rawStart.toUtc();
                           } else if (rawStart is String) {
                             start = DateTime.tryParse(rawStart)?.toUtc();
                           }

                           // If we have no end time, assume 1 hour duration from start
                           if (end == null && start != null) {
                              end = start.add(const Duration(hours: 1));
                           }

                           // Normalize End Time to UTC for comparison
                           if (end != null) {
                             end = end.toUtc();
                           }
                           final nowUtc = now.toUtc();

                           // Check Visibility After Preference (Default to 0 if not saved)
                           int visibilityAfter = e['visibilityAfterMinutes'] ?? 0;
                           
                           // Filter: Remove strictly after EndTime + Visibility Duration
                           if (end != null) {
                             final expirationTime = end.add(Duration(minutes: visibilityAfter));
                             if (expirationTime.isBefore(nowUtc)) {
                               return false;
                             }
                           }
                           
                           // Safety: If no timestamps at all, remove it to be safe/clean
                           if (end == null && start == null) {
                             return false;
                           }

                           return true;
                        }).toList();

                        final pastIntents = combinedEvents.where((event) {
                          return event['isVirtual'] != true &&
                              _isPastRegisteredEvent(event, now);
                        }).toList();
                        final normalizedPastIntentFilter = _pastIntentFilter.trim().toLowerCase();
                        final visiblePastIntents = normalizedPastIntentFilter.isEmpty
                            ? pastIntents
                            : pastIntents.where((event) {
                                final intent = (event['intent'] ?? '').toString().toLowerCase();
                                return intent.contains(normalizedPastIntentFilter);
                              }).toList();

                        // DEBUG MODE: SHOW ALL EVENTS NO FILTER
                        // final activeEvents = eventService.myEvents;
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('My Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            
                            const SizedBox(height: 12),
                            if (activeEvents.isEmpty)
                               Container(
                                 width: double.infinity,
                                 padding: const EdgeInsets.all(16),
                                 decoration: BoxDecoration(
                                   color: Colors.white.withValues(alpha: 0.1),
                                   borderRadius: BorderRadius.circular(12),
                                 ),
                                 child: const Text("You haven't joined any active events.", style: TextStyle(color: Colors.white54)),
                               )
                            else
                               SizedBox(
                                 height: 80, // Matched to Favorites Dimensions (80)
                                 child: ListView.builder(
                                   scrollDirection: Axis.horizontal,
                                   itemCount: activeEvents.length,
                                   itemBuilder: (context, index) {
                                      final event = activeEvents[index];
                                      final title = event['eventTitle'] ?? 'Event';
                                      final intent = event['intent'] ?? '';
                                      
                                      // Robust StartTime handling
                                      dynamic rawStart = event['startTime'] ?? event['timestamp'];
                                      DateTime? start;
                                      if (rawStart is Timestamp) {
                                        start = rawStart.toDate();
                                      } else if (rawStart is DateTime) {
                                        start = rawStart;
                                      }
                                      
                                      final dateStr = start != null 
                                          ? DateFormat('MMM d, h:mm a').format(start) 
                                          : 'Recent';
                                      
                                      return Container(
                                        width: 140, // Matched to Favorites Dimensions (140)
                                        margin: const EdgeInsets.only(right: 12),
                                        padding: const EdgeInsets.all(12), // Restored padding
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12), // Restored radius
                                          border: Border.all(color: Colors.white12),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title, 
                                                  maxLines: 1, 
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13) // Restored font size
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  intent.isNotEmpty ? intent : 'No intent', 
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11) // Restored font size
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                const Icon(Icons.event, color: Colors.white54, size: 10),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    dateStr,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                                                  ),
                                                ),
                                              ],
                                            )
                                          ],
                                        ),
                                      );
                                   },
                                 ),
                               ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                const Text(
                                  'Past Intents',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Spacer(),
                                if (normalizedPastIntentFilter.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Text(
                                      '${visiblePastIntents.length} match${visiblePastIntents.length == 1 ? '' : 'es'}',
                                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: normalizedPastIntentFilter.isEmpty
                                      ? 'Filter past intents'
                                      : 'Change past intent filter',
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    normalizedPastIntentFilter.isEmpty
                                        ? Icons.filter_alt_outlined
                                        : Icons.filter_alt,
                                    color: normalizedPastIntentFilter.isEmpty
                                        ? Colors.white70
                                        : Colors.amberAccent,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    final controller = TextEditingController(text: _pastIntentFilter);
                                    final filter = await showDialog<String>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('Filter Past Intents'),
                                        content: TextField(
                                          controller: controller,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                            hintText: 'Search a word or phrase',
                                          ),
                                          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(dialogContext).pop(''),
                                            child: const Text('Clear'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                                            child: const Text('Apply'),
                                          ),
                                        ],
                                      ),
                                    );
                                    controller.dispose();
                                    if (filter != null && mounted) {
                                      setState(() => _pastIntentFilter = filter);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'A private reflection of what you chose to focus on and when.',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            if (visiblePastIntents.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  normalizedPastIntentFilter.isEmpty
                                      ? 'Past intents will appear here after their event has ended.'
                                      : 'No past intents match this filter.',
                                  style: const TextStyle(color: Colors.white54),
                                ),
                              )
                            else
                              // Fixed-height, independently-scrollable box -
                              // safe now the outer container is a
                              // SingleChildScrollView, not a ListView.
                              SizedBox(
                                height: 264,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: visiblePastIntents.length,
                                  itemBuilder: (context, index) {
                                    final event = visiblePastIntents[index];
                                    final intent = (event['intent'] ?? 'No intent').toString();
                                    final start = _registeredEventDate(
                                      event['startTime'] ?? event['timestamp'],
                                    );
                                    final date = start == null
                                        ? 'Date unavailable'
                                        : DateFormat('MMM d, yyyy, h:mm a').format(start);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.history, color: Colors.amberAccent, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(intent, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.amberAccent, fontSize: 13)),
                                                const SizedBox(height: 2),
                                                Text(date, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Edit past intent',
                                            onPressed: () => _editPastIntent(event),
                                            icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 19),
                                          ),
                                          IconButton(
                                            tooltip: 'Delete past intent',
                                            onPressed: () => _deletePastIntent(event),
                                            icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 19),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Support Requests: kept separate from event-based Past Intents
                    // deliberately, since the timing/expiry logic above is fragile
                    // and support requests have nothing to do with events.
                    _buildSupportIntentsSection(),
                    const SizedBox(height: 24),

                    // Favorites Section
                    const Text(
                      'My Favorites Collection',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    _buildFavoritesList(),

                    const SizedBox(height: 24),
                    // FIND A NEW GROUP LINK - Wrapped in Condition
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('system_settings').doc('app_config').snapshots(),
                      builder: (context, snapshot) {
                        bool show = true;
                        if (snapshot.hasData && snapshot.data!.exists) {
                           show = (snapshot.data!.data() as Map<String, dynamic>)['show_niche_chat_rooms'] ?? true;
                        }
                        if (!show) return const SizedBox.shrink();
                        
                        return Center(
                             child: TextButton.icon(
                                 onPressed: () {
                                    Navigator.push(
                                         context,
                                         MaterialPageRoute(builder: (context) => const CommunityGroupsScreen())
                                    );
                                 },
                                 icon: const Icon(Icons.search, color: Colors.amber),
                                 label: const Text("Find Chatrooms", style: TextStyle(color: Colors.amber)),
                             ),
                        );
                      }
                    ),
                    const Divider(color: Colors.white12),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
                      title: const Text('My Harmony Vault', style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                        'Manage saved photos for Common Room comments',
                        style: TextStyle(color: Colors.white54),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MediaVaultScreen()),
                        );
                      },
                    ),
                ],
                ),
              ),

              // 2. Settings Tab (Technical/Personal)
              Consumer2<UserService, SubscriptionService>(
                builder: (context, userService, subscriptionService, _) {
                  final authUser = FirebaseAuth.instance.currentUser;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                       ListTile(
                         leading: const Icon(Icons.stars, color: Colors.amber),
                         title: const Text('Manage Subscription', style: TextStyle(color: Colors.white)),
                         subtitle: Text(
                           subscriptionService.isVip
                               ? 'Early Access'
                               : (subscriptionService.isSubscribed ? 'Active Plan' : 'Subscription required'),
                           style: const TextStyle(color: Colors.white54),
                         ),
                         trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                         onTap: () async {
                              // loading
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
                              );

                              try {
                                // 1. Check if VIP (Local Override) - Do NOT show Customer Center
                                if (subscriptionService.isVip) {
                                  if (context.mounted) Navigator.pop(context); // Close loader
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      backgroundColor: const Color(0xFF2A2A2A),
                                      title: const Text('Early Access Enabled', style: TextStyle(color: Colors.amber)),
                                      content: const Text(
                                        'You currently have full access enabled.\n\nNo subscription management is needed right now.',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('OK', style: TextStyle(color: Colors.amber)),
                                        )
                                      ],
                                    )
                                  );
                                  return;
                                }

                                // 2. Refresh Status from RevenueCat
                                await subscriptionService.refreshSubscriptionStatus();

                                // 3. Decide: Customer Center OR Paywall
                                // We check 'isSubscribed' again after refresh.
                                // NOTE: We specifically check the underlying Real Subscription status if needed, 
                                // but 'isSubscribed' covers both. Since we handled isVip above, 
                                // isSubscribed here implies Real Subscription.
                                
                                if (subscriptionService.isSubscribed) {
                                  if (context.mounted) Navigator.pop(context); // Close loader
                                  await subscriptionService.showCustomerCenter();
                                } else {
                                  await subscriptionService.showPaywall();
                                  if (context.mounted) Navigator.pop(context); // Close loader (paywall handles its own dismissal)
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  // Fallback: If network fails, offer Paywall anyway? No, show error.
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                                }
                              }
                         },
                       ),
                       const Divider(color: Colors.white12),
                       const Divider(color: Colors.white12),
                       ListTile(
                         leading: const Icon(Icons.badge_outlined, color: Colors.white),
                         title: const Text('Profile Information', style: TextStyle(color: Colors.white)),
                         subtitle: Text(
                           '${userService.userName} • ${userService.timeZone}',
                           style: const TextStyle(color: Colors.white54),
                         ),
                         trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                         onTap: () {
                           Navigator.push(
                             context,
                             MaterialPageRoute(builder: (_) => const PersonalInformationScreen()),
                           );
                         },
                       ),
                       const Divider(color: Colors.white12),
                       ListTile(
                         leading: const Icon(Icons.logout, color: Colors.redAccent),
                         title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                         onTap: () async {
                           final confirmed = await showDialog<bool>(
                             context: context,
                             builder: (ctx) => AlertDialog(
                               backgroundColor: const Color(0xFF2A2A2A),
                               title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                               content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white70)),
                               actions: [
                                 TextButton(
                                   onPressed: () => Navigator.pop(ctx, false),
                                   child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                                 ),
                                 TextButton(
                                   onPressed: () => Navigator.pop(ctx, true),
                                   child: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                                 ),
                               ],
                             ),
                           );
                           if (confirmed == true && context.mounted) {
                             final authUser = FirebaseAuth.instance.currentUser;
                             final prefs = await SharedPreferences.getInstance();
                             await prefs.setBool('has_existing_account', true);
                             final signedInEmail = authUser?.email?.trim() ?? '';
                             if (signedInEmail.isNotEmpty) {
                               await prefs.setString('last_login_email', signedInEmail);
                             }

                             await FirebaseAuth.instance.signOut();
                             await Provider.of<UserService>(context, listen: false).clearUser();
                             if (context.mounted) {
                               Navigator.pushAndRemoveUntil(
                                 context,
                                 MaterialPageRoute(builder: (_) => const LoginScreen()),
                                 (_) => false,
                               );
                             }
                           }
                         },
                       ),
                    ],
                  );
                }
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('youtube_sections').snapshots(),
      builder: (context, sectionsSnapshot) {
        final sectionTitles = <String, String>{};
        if (sectionsSnapshot.hasData) {
          for (var doc in sectionsSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            sectionTitles[doc.id] = data['title'] ?? 'Generic';
          }
        }

        return Consumer<FavoritesService>(
          builder: (context, favoritesService, _) {
            final favorites = favoritesService.favorites;
            if (favorites.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'No favorites yet.\nTap the heart icon on events to add them here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
              );
            }

            final categories = <String, List<Map<String, dynamic>>>{};
            for (var item in favorites) {
              final sectionId = item['sectionId'] as String?;
              String displayTitle = 'General';

              if (sectionId != null && sectionId.isNotEmpty) {
                 displayTitle = sectionTitles[sectionId] ?? 'General';
              }

              categories.putIfAbsent(displayTitle, () => []).add(item);
            }

            final categoryKeys = categories.keys.toList()..sort();

            return SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: categoryKeys.length,
                itemBuilder: (context, index) {
                  final category = categoryKeys[index];
                  final items = categories[category]!;

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CategoryFavoritesScreen(
                            categoryName: category,
                            favorites: items,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            category,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${items.length} items',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, {IconData? icon, Color? color}) {
    return Column(
      children: [
        if (icon != null) ...[
          Icon(icon, color: color ?? Colors.white, size: 24),
          const SizedBox(height: 4),
        ],
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Future<int> _fetchWorldwideUserTotal() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .get()
          .timeout(const Duration(seconds: 8));
      final data = doc.data() ?? const <String, dynamic>{};
      final liveCount = (data['worldwideUserTotal'] as num?)?.toInt() ?? 0;
      final adjustment = (data['worldwideUserTotalAdjustment'] as num?)?.toInt() ?? 0;
      return liveCount + adjustment;
    } catch (e) {
      debugPrint('[TotalUsers] fetch error: $e');
      return 0;
    }
  }

  Future<int> _fetchRegionalUserTotal() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .get()
          .timeout(const Duration(seconds: 8));
      final data = doc.data() ?? const <String, dynamic>{};
      final totals = Map<String, dynamic>.from(
        data['regionalUserTotals'] as Map? ?? const <String, dynamic>{},
      );
      final adjustments = Map<String, dynamic>.from(
        data['regionalUserCountAdjustments'] as Map? ?? const <String, dynamic>{},
      );
      final offsets = Map<String, dynamic>.from(
        data['regionalUserOffsets'] as Map? ?? const <String, dynamic>{},
      );
      // iOS and Android report different timezone names, so fall back to UTC offset.
      var region = UserService().timeZone;
      if (!totals.containsKey(region)) {
        final deviceOffset = DateTime.now().timeZoneOffset.inHours;
        for (final entry in offsets.entries) {
          if ((entry.value as num?)?.toInt() == deviceOffset &&
              totals.containsKey(entry.key)) {
            region = entry.key;
            break;
          }
        }
      }
      final liveCount = (totals[region] as num?)?.toInt() ?? 0;
      final adjustment = (adjustments[region] as num?)?.toInt() ?? 0;
      return liveCount + adjustment;
    } catch (e) {
      debugPrint('[TimeZoneUsers] fetch error: $e');
      return 0;
    }
  }

  Widget _buildTotalUsersStatItem() {
    return FutureBuilder<int>(
      future: _totalUsersFuture,
      builder: (context, snapshot) {
        final value = snapshot.hasData ? '${snapshot.data}' : '...';
        return _buildStatItem('Total Users', value);
      },
    );
  }

  Widget _buildTimeZoneUsersStatItem() {
    return FutureBuilder<int>(
      future: _timeZoneUsersFuture,
      builder: (context, snapshot) {
        final value = snapshot.hasData ? '${snapshot.data}' : '...';
        return _buildStatItem('Your Time Zone', value);
      },
    );
  }

  Widget _buildLikesReceivedStatItem() {
    final uid = UserService().userId;
    if (uid.isEmpty) {
      return _buildStatItem('Likes Recv.', '0', icon: Icons.thumb_up, color: Colors.greenAccent);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('community_posts')
          .where('userId', isEqualTo: uid)
          .snapshots(),
      builder: (context, postsSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collectionGroup('messages')
              .where('userId', isEqualTo: uid)
              .snapshots(),
          builder: (context, messagesSnapshot) {
            var totalLikes = 0;

            if (postsSnapshot.hasData) {
              for (final doc in postsSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                totalLikes += (data['likes'] as int?) ?? 0;
              }
            }

            if (messagesSnapshot.hasData) {
              for (final doc in messagesSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                totalLikes += (data['likes'] as int?) ?? 0;
              }
            }

            return _buildStatItem(
              'Likes Recv.',
              '$totalLikes',
              icon: Icons.thumb_up,
              color: Colors.greenAccent,
            );
          },
        );
      },
    );
  }

  Widget _buildSupportReceivedStatItem() {
    final uid = UserService().userId;
    if (uid.isEmpty) {
      return const Column(
        children: [
          Icon(Icons.front_hand, color: Colors.white, size: 24),
          SizedBox(height: 4),
          Text('0', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(height: 4),
          Text('Support Recv.', style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('app_config').doc('community_support').snapshots(),
      builder: (context, configSnap) {
        final supportConfig = configSnap.data?.data() ?? const <String, dynamic>{};

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('community_posts')
              .where('userId', isEqualTo: uid)
              .where('isSupportRequest', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            var totalSupport = 0;
            if (snapshot.hasData) {
              for (final doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                totalSupport += (data['supportTapCount'] as int?) ?? 0;
              }
            }

            return Column(
              children: [
                SupportIcon(config: supportConfig, size: 24, fallbackColor: Colors.white),
                const SizedBox(height: 4),
                Text(
                  '$totalSupport',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text('Support Recv.', style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMyCommentsCountStatItem() {
    final uid = UserService().userId;
    if (uid.isEmpty) {
      return _buildStatItem('Posts', '0', icon: Icons.chat_bubble_outline, color: Colors.amberAccent);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('community_posts')
          .where('userId', isEqualTo: uid)
          .snapshots(),
      builder: (context, postsSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collectionGroup('messages')
              .where('userId', isEqualTo: uid)
              .snapshots(),
          builder: (context, messagesSnapshot) {
            final postCount = postsSnapshot.hasData ? postsSnapshot.data!.docs.length : 0;
            final messageCount = messagesSnapshot.hasData ? messagesSnapshot.data!.docs.length : 0;
            final totalComments = postCount + messageCount;

            return _buildStatItem(
              'Posts',
              '$totalComments',
              icon: Icons.chat_bubble_outline,
              color: Colors.amberAccent,
            );
          },
        );
      },
    );
  }

  Widget _buildMostLikedCommentCard() {
    final uid = UserService().userId;
    if (uid.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          'Your personal liked comments will appear here after you post.',
          style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('community_posts')
            .where('userId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text(
              'Most liked comment is temporarily unavailable.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            );
          }

          String topComment = 'Post your first comment to start your activity.';
          var likes = 0;

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final docs = snapshot.data!.docs;
            docs.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aLikes = (aData['likes'] as int?) ?? 0;
              final bLikes = (bData['likes'] as int?) ?? 0;
              return bLikes.compareTo(aLikes);
            });

            final data = docs.first.data() as Map<String, dynamic>;
            topComment = (data['content'] as String?)?.trim().isNotEmpty == true
                ? data['content'] as String
                : 'Comment text unavailable';
            likes = (data['likes'] as int?) ?? 0;
          }

            final commentPreview = '"$topComment"';
            final canExpand = topComment.isNotEmpty &&
                topComment != 'Post your first comment to start your activity.' &&
                topComment != 'Comment text unavailable';

            void showExpandedComment() {
              showDialog<void>(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    title: const Text(
                      'My Most Liked Post',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            topComment,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.35,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Icon(
                                Icons.thumb_up,
                                size: 16,
                                color: Colors.greenAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$likes',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.amberAccent),
                        ),
                      ),
                    ],
                  );
                },
              );
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canExpand ? showExpandedComment : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'My Most Liked Post',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      const Icon(Icons.thumb_up, size: 12, color: Colors.greenAccent),
                      const SizedBox(width: 4),
                      Text(
                        '$likes',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    commentPreview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                  ),
                  if (canExpand) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Tap anywhere on this card to expand',
                      style: TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
        },
      ),
    );
  }

  Widget _buildCommunityPulseCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('community_posts').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text(
              'Most liked comment is temporarily unavailable.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            );
          }

          String topComment = 'Your community activity will appear here after you post.';
          var likes = 0;

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final docs = snapshot.data!.docs;
            docs.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aLikes = (aData['likes'] as int?) ?? 0;
              final bLikes = (bData['likes'] as int?) ?? 0;
              if (aLikes != bLikes) return bLikes.compareTo(aLikes);
              // Tie on likes: prefer the more recent comment.
              final aTime = (aData['timestamp'] as Timestamp?)?.toDate();
              final bTime = (bData['timestamp'] as Timestamp?)?.toDate();
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            });

            final data = docs.first.data() as Map<String, dynamic>;
            topComment = (data['content'] as String?)?.trim().isNotEmpty == true
                ? data['content'] as String
                : 'Comment text unavailable';
            likes = (data['likes'] as int?) ?? 0;
          }

                    final commentPreview = '"$topComment"';
          final canExpand = topComment.isNotEmpty &&
              topComment != 'Your community activity will appear here after you post.' &&
              topComment != 'Comment text unavailable';

          void showExpandedComment() {
            showDialog<void>(
              context: context,
              builder: (dialogContext) {
                return AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  title: const Text(
                    'Overall Most Liked Post',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          topComment,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.35,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(
                              Icons.thumb_up,
                              size: 16,
                              color: Colors.greenAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$likes',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: Colors.amberAccent),
                      ),
                    ),
                  ],
                );
              },
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canExpand ? showExpandedComment : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Overall Most Liked Post',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    const Icon(Icons.thumb_up, size: 12, color: Colors.greenAccent),
                    const SizedBox(width: 4),
                    Text(
                      '$likes',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  commentPreview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                ),
                if (canExpand) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Tap anywhere on this card to expand',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMostSupportedRequestCard() {
    final uid = UserService().userId;
    if (uid.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          'Your most supported request will appear here after you post one.',
          style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('app_config')
            .doc('community_support')
            .snapshots(),
        builder: (context, supportConfigSnap) {
          final supportConfig = supportConfigSnap.data?.data() ?? const <String, dynamic>{};

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('community_posts')
                .where('userId', isEqualTo: uid)
                .where('isSupportRequest', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Most supported request is temporarily unavailable.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                );
              }

              String topContent = 'Request community support to start your activity.';
              var supportCount = 0;

              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                final docs = snapshot.data!.docs;
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aCount = (aData['supportTapCount'] as int?) ?? 0;
                  final bCount = (bData['supportTapCount'] as int?) ?? 0;
                  return bCount.compareTo(aCount);
                });

                final data = docs.first.data() as Map<String, dynamic>;
                topContent = (data['content'] as String?)?.trim().isNotEmpty == true
                    ? data['content'] as String
                    : 'Request text unavailable';
                supportCount = (data['supportTapCount'] as int?) ?? 0;
              }

              final contentPreview = '"$topContent"';
              final canExpand = topContent.isNotEmpty &&
                  topContent != 'Request community support to start your activity.' &&
                  topContent != 'Request text unavailable';

              void showExpandedRequest() {
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) {
                    return AlertDialog(
                      backgroundColor: const Color(0xFF1E1E1E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      title: const Text(
                        'My Most Supported Request',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              topContent,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.35,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                SupportIcon(config: supportConfig, size: 16, fallbackColor: Colors.amberAccent),
                                const SizedBox(width: 6),
                                Text(
                                  '$supportCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close', style: TextStyle(color: Colors.amberAccent)),
                        ),
                      ],
                    );
                  },
                );
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: canExpand ? showExpandedRequest : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'My Most Supported Request',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        SupportIcon(config: supportConfig, size: 12, fallbackColor: Colors.amberAccent),
                        const SizedBox(width: 4),
                        Text(
                          '$supportCount',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      contentPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                    ),
                    if (canExpand) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Tap anywhere on this card to expand',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  int _calculateJoinStreakDays(List<Map<String, dynamic>> events) {
    final joinedDays = <DateTime>{};

    for (final event in events) {
      final timestamp = event['timestamp'] ?? event['startTime'];
      DateTime? date;

      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else if (timestamp is String) {
        date = DateTime.tryParse(timestamp);
      }

      if (date != null) {
        final local = date.toLocal();
        joinedDays.add(DateTime(local.year, local.month, local.day));
      }
    }

    if (joinedDays.isEmpty) return 0;

    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    var streak = 0;

    while (joinedDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  String _formatStreakLabel(int streakDays) {
    if (streakDays == 1) return '1 Day';
    return '$streakDays Days';
  }
}
