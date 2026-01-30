import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/favorites_service.dart';
import '../services/group_service.dart';
import '../services/event_service.dart';
import '../services/user_service.dart';
import '../widgets/favorite_item_card.dart';
import 'category_favorites_screen.dart';
import 'chat_screen.dart';
import 'community_groups_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
              ListView(
                padding: const EdgeInsets.all(16),
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
                       return Card(
                          elevation: 4,
                          color: Colors.white.withOpacity(0.1),
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
                                    _buildStatItem('Events Joined', '${eventService.myEvents.length}'), 
                                    _buildStatItem('Streak', '3 Days'),
                                    _buildStatItem('Total Users', '152'),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Divider(color: Colors.white24),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance.collectionGroup('messages').where('userId', isEqualTo: UserService().userId).snapshots(),
                                      builder: (context, snapshot) {
                                        int total = 0;
                                        if (snapshot.hasData) {
                                          for (var doc in snapshot.data!.docs) {
                                            final data = doc.data() as Map<String, dynamic>;
                                            total += (data['likes'] as int? ?? 0);
                                          }
                                        }
                                        return _buildStatItem('Likes Recv.', '$total', icon: Icons.thumb_up, color: Colors.greenAccent);
                                      }
                                    ),
                                    _buildStatItem('Comments', '15', icon: Icons.chat_bubble_outline, color: Colors.amberAccent),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  // Live "Most Liked Comment" Query - From Community Room
                                  child: StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('community_posts')
                                        .orderBy('likes', descending: true)
                                        .limit(1)
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasError) {
                                        return const Text("Most Liked Comment: (Needs Index)", style: TextStyle(color: Colors.white38, fontSize: 10));
                                      }
                                      
                                      String topComment = "No comments yet";
                                      int likes = 0;
                                      
                                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                        final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                                        topComment = data['content'] ?? "Hidden"; // 'content' not 'text' in community_posts
                                        likes = data['likes'] ?? 0;
                                      }

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.star, color: Colors.amber, size: 16),
                                              const SizedBox(width: 8),
                                              const Text('Most Liked (Community)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                              const Spacer(),
                                              const Icon(Icons.thumb_up, size: 12, color: Colors.greenAccent),
                                              const SizedBox(width: 4),
                                              Text('$likes', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '"$topComment"',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                                          ),
                                        ],
                                      );
                                    }
                                  ),
                                ),
                                const SizedBox(height: 16),
                                StreamBuilder<DocumentSnapshot>(
                                  stream: FirebaseFirestore.instance.collection('system_settings').doc('trending_intent').snapshots(),
                                  builder: (context, snapshot) {
                                    String intent = "Loading..."; // Default while connecting
                                    
                                    if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
                                      final data = snapshot.data!.data() as Map<String, dynamic>;
                                      intent = data['currentIntent'] ?? "Harmony";
                                    } else if (!snapshot.hasData) {
                                       // Keep default "Loading..."
                                    } else {
                                       intent = "Harmony"; // Fallback if doc missing
                                    }

                                    return Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(top: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.purple.shade900.withOpacity(0.4), Colors.pink.shade900.withOpacity(0.4)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.pinkAccent.withOpacity(0.3)),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: const [
                                              Icon(Icons.bolt, color: Colors.amber, size: 18),
                                              SizedBox(width: 8),
                                              Text('COMMUNITY PULSE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            intent.toUpperCase(),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 1.2, shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                ),
                              ],
                            ),
                          ),
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
                                  color: Colors.white.withOpacity(0.1),
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
                                                color: Colors.white.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.white12),
                                              ),
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor: color.withOpacity(0.2),
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
                                      if (m['eventId'] != event.id) return false;
                                      
                                      // Check expiration of this specific history item
                                      dynamic rawEnd = m['endTime'];
                                      DateTime? end;
                                      if (rawEnd is Timestamp) end = rawEnd.toDate();
                                      else if (rawEnd is DateTime) end = rawEnd;
                                      else if (rawEnd is String) end = DateTime.tryParse(rawEnd);
                                      
                                      // Fallback for End Time
                                      if (end == null) {
                                          dynamic rawStart = m['startTime'] ?? m['timestamp'];
                                          DateTime? start;
                                          if (rawStart is Timestamp) start = rawStart.toDate();
                                          else if (rawStart is DateTime) start = rawStart;
                                          else if (rawStart is String) start = DateTime.tryParse(rawStart);
                                          
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
                           if (rawEnd is Timestamp) end = rawEnd.toDate();
                           else if (rawEnd is DateTime) end = rawEnd; // Handle optimistic updates
                           else if (rawEnd is String) end = DateTime.tryParse(rawEnd); // Fallback

                           // Robust StartTime handling to catch missing EndTime
                           dynamic rawStart = e['startTime'] ?? e['timestamp'];
                           DateTime? start;
                           if (rawStart is Timestamp) start = rawStart.toDate().toUtc(); // Normalize to UTC
                           else if (rawStart is DateTime) start = rawStart.toUtc();
                           else if (rawStart is String) start = DateTime.tryParse(rawStart)?.toUtc();

                           // If we have no end time, assume 1 hour duration from start
                           if (end == null && start != null) {
                              end = start.add(const Duration(hours: 1));
                           }

                           // Normalize End Time to UTC for comparison
                           if (end != null) end = end.toUtc();
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
                           if (end == null && start == null) return false;

                           return true;
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
                                   color: Colors.white.withOpacity(0.1),
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
                                      if (rawStart is Timestamp) start = rawStart.toDate();
                                      else if (rawStart is DateTime) start = rawStart;
                                      
                                      final dateStr = start != null 
                                          ? DateFormat('MMM d, h:mm a').format(start) 
                                          : 'Recent';
                                      
                                      return Container(
                                        width: 140, // Matched to Favorites Dimensions (140)
                                        margin: const EdgeInsets.only(right: 12),
                                        padding: const EdgeInsets.all(12), // Restored padding
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
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
                          ],
                        );
                      },
                    ),
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
                ],
              ),

              // 2. Settings Tab (Technical/Personal)
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                   ListTile(
                     leading: const Icon(Icons.email, color: Colors.white),
                     title: const Text('Email', style: TextStyle(color: Colors.white)),
                     subtitle: const Text('user@example.com', style: TextStyle(color: Colors.white54)),
                     trailing: const Icon(Icons.edit, color: Colors.white54, size: 16),
                     onTap: () {},
                   ),
                   const Divider(color: Colors.white12),
                   ListTile(
                     leading: const Icon(Icons.lock, color: Colors.white),
                     title: const Text('Change Password', style: TextStyle(color: Colors.white)),
                     trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                     onTap: () {},
                   ),
                   const Divider(color: Colors.white12),
                   ListTile(
                     leading: const Icon(Icons.notifications, color: Colors.white),
                     title: const Text('Notifications', style: TextStyle(color: Colors.white)),
                     trailing: Switch(value: true, onChanged: (val){}, activeColor: Colors.amber),
                   ),
                   const Divider(color: Colors.white12),
                   ListTile(
                     leading: const Icon(Icons.logout, color: Colors.redAccent),
                     title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                     onTap: () {},
                   ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupItem(BuildContext context, String name, IconData icon, Color color, GroupService groupService) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.2),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(name, style: const TextStyle(color: Colors.white)),
      subtitle: const Text("Tap to open chat", style: TextStyle(color: Colors.white38, fontSize: 10)),
      trailing: IconButton(
        icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 20),
        tooltip: 'Leave Chat Room',
        onPressed: () async {
           // We need to find the ID if possible, but leaveGroup handles name lookup internally
           await groupService.leaveGroup(name);
           if (context.mounted) {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Left $name")));
           }
        },
      ),
      onTap: () {
          // Navigate to Chat
          // Safe lookup for ID
          final group = groupService.myGroups.firstWhere((g) => g['name'] == name, orElse: () => {});
          if (group.isNotEmpty && group['id'] != null) {
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
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
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
                        color: Colors.white.withOpacity(0.1),
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
                              color: Colors.white.withOpacity(0.7),
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
}
