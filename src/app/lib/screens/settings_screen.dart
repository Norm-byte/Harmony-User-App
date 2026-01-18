import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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
                                    _buildStatItem('Likes Recv.', '42', icon: Icons.thumb_up, color: Colors.greenAccent),
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
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.star, color: Colors.amber, size: 16),
                                          const SizedBox(width: 8),
                                          const Text("Most Liked Comment", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                                          const Spacer(),
                                          const Text("28 Likes", style: TextStyle(color: Colors.white54, fontSize: 10)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        '"Sending love and light to everyone across the globe from London! 🌍✨"',
                                        style: TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                     }
                   ),
                    const SizedBox(height: 24),

                    // My Groups
                    Consumer<GroupService>(
                      builder: (context, groupService, _) {
                        return Card(
                          elevation: 4,
                          color: Colors.white.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                             padding: const EdgeInsets.all(16),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                  const Text('My Forums', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 16),
                                  if (groupService.myGroups.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: Text("You haven't joined any forums yet.", style: TextStyle(color: Colors.white54)),
                                    )
                                  else
                                    ...groupService.myGroups.map((group) {
                                      final icon = group['iconCode'] != null
                                          ? IconData(group['iconCode'], fontFamily: 'MaterialIcons')
                                          : Icons.forum;
                                      final color = group['colorValue'] != null
                                          ? Color(group['colorValue'])
                                          : Colors.blue;

                                      return Column(
                                        children: [
                                          _buildGroupItem(context, group['name'], icon, color, groupService),
                                          const Divider(color: Colors.white10),
                                        ],
                                      );
                                    }).toList(),
                               ],
                             ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // My Events (Scrollable Cards)
                    Consumer<EventService>(
                      builder: (context, eventService, _) {
                        final now = DateTime.now();
                        final activeEvents = eventService.myEvents.where((e) {
                           // Robust Timestamp handling
                           dynamic rawEnd = e['endTime'];
                           DateTime? end;
                           if (rawEnd is Timestamp) end = rawEnd.toDate();
                           else if (rawEnd is DateTime) end = rawEnd; // Handle optimistic updates
                           else if (rawEnd is String) end = DateTime.tryParse(rawEnd); // Fallback

                           // Robust StartTime handling to catch missing EndTime
                           dynamic rawStart = e['startTime'] ?? e['timestamp'];
                           DateTime? start;
                           if (rawStart is Timestamp) start = rawStart.toDate();
                           else if (rawStart is DateTime) start = rawStart;
                           else if (rawStart is String) start = DateTime.tryParse(rawStart);

                           // If we have no end time, assume 1 hour duration from start
                           if (end == null && start != null) {
                              end = start.add(const Duration(hours: 1));
                           }

                           // Check Visibility After Preference (Default to 0 if not saved)
                           int visibilityAfter = e['visibilityAfterMinutes'] ?? 0;
                           
                           // Filter: Remove strictly after EndTime + Visibility Duration
                           if (end != null) {
                             final expirationTime = end.add(Duration(minutes: visibilityAfter));
                             if (expirationTime.isBefore(now)) {
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
                    // FIND A NEW GROUP LINK
                    Center(
                         child: TextButton.icon(
                             onPressed: () {
                                Navigator.push(
                                     context,
                                     MaterialPageRoute(builder: (context) => const CommunityGroupsScreen())
                                );
                             },
                             icon: const Icon(Icons.search, color: Colors.amber),
                             label: const Text("Find More Forums", style: TextStyle(color: Colors.amber)),
                         ),
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
        tooltip: 'Leave Forum',
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
