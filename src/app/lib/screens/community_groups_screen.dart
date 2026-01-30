import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' as Foundation;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/group_service.dart';
import '../services/subscription_service.dart';
import '../widgets/gradient_scaffold.dart';
import '../services/usage_service.dart';

class CommunityGroupsScreen extends StatelessWidget {
  const CommunityGroupsScreen({super.key});

  IconData _getIconData(String? name) {
      switch (name) {
        case 'public': return Icons.public;
        case 'psychology': return Icons.psychology;
        case 'favorite': return Icons.favorite;
        case 'wb_sunny': return Icons.wb_sunny;
        case 'nature': return Icons.nature;
        case 'self_improvement': return Icons.self_improvement;
        case 'spa': return Icons.spa;
        case 'music_note': return Icons.music_note;
        default: return Icons.group;
      }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Community Chat Rooms'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Consumer<GroupService>(
        builder: (context, groupService, _) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('community_groups')
                .where('isPublished', isEqualTo: true)
                // Removed server-side sort to ensure visibility even if index is building
                .snapshots(),
            builder: (context, snapshot) {
              
              if (snapshot.hasError) {
                  // In production, we might log this. For user, show friendly message.
                  // We treat 'failed-precondition' (missing index) as "Groups being prepared" 
                  // to avoid scaring users while indexes build.
                  
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.coffee, size: 48, color: Colors.white54),
                        SizedBox(height: 16),
                        Text(
                          'Chat Rooms are being prepared...',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Please check back soon!',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
              }

              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));

              // Client-side sort to be safe
              final docs = snapshot.data!.docs.toList();
              docs.sort((a, b) {
                 final aData = a.data() as Map<String, dynamic>;
                 final bData = b.data() as Map<String, dynamic>;
                 final aSort = aData['sortOrder'] as int? ?? 0;
                 final bSort = bData['sortOrder'] as int? ?? 0;
                 return aSort.compareTo(bSort);
              });
              
              if (docs.isEmpty) {
                 return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.hourglass_empty, size: 48, color: Colors.white54),
                        SizedBox(height: 16),
                        Text(
                          'New chat rooms are on their way!',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                         Text(
                          'Our community managers are curating\nexciting new spaces for you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final name = data['name'] ?? 'Unknown Chat Room';
                  final description = data['description'] ?? '';
                  final memberCount = data['memberCount'] ?? 0;
                  final iconName = data['iconName'] as String?;
                  final colorValue = data['colorValue'] as int? ?? Colors.blue.value;
                  final isPaused = data['isPaused'] == true;
                  
                  // Construct group map for Service compatibility
                  final groupMap = {
                      'id': docs[index].id,
                      'name': name, // Currently acting as ID in Service
                      'description': description,
                      'members': '$memberCount', // Service expects string for display currently
                      'iconCode': _getIconData(iconName).codePoint,
                      'colorValue': colorValue
                  };

                  final isJoined = groupService.isJoined(name);

                  return Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: Colors.white.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: InkWell(
                      onTap: () async {
                        if (isJoined) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Already a member of $name')),
                          );
                        } else {
                          // Check Subscription Limits
                          final subscriptionService = context.read<SubscriptionService>();
                          final usageService = context.read<UsageService>();
                          final int maxGroups = usageService.maxActiveForums;

                          // Check if user has reached their limit
                          if (groupService.myGroups.length >= maxGroups) {
                             // Prompt to Upgrade
                             try {
                               // Optional: Show specific message "You reached your limit of $maxGroups chat rooms"
                               final didSubscribe = await subscriptionService.showPaywall();
                               if (!didSubscribe) return; // User cancelled
                             } catch (e) {
                               debugPrint("Paywall error: $e");
                               if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Could not load subscription options. Please try again later."))
                                  );
                               }
                               return;
                             }
                          }

                          await groupService.joinGroup(groupMap);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Joined $name!')),
                            );
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Color(colorValue).withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getIconData(iconName),
                                color: Color(colorValue),
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (isPaused)
                                    Container(
                                      margin: const EdgeInsets.only(top: 2, bottom: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber),
                                      ),
                                      child: const Text('MAINTENANCE', 
                                        style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)
                                      ),
                                    ),
                                  if (description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        description,
                                        style: const TextStyle(color: Colors.white70),
                                      ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.group, size: 14, color: Colors.white54),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$memberCount members',
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isJoined ? Colors.green.withOpacity(0.3) : null,
                                border: Border.all(color: isJoined ? Colors.green : Colors.white30),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isJoined ? 'JOINED' : 'JOIN', 
                                style: TextStyle(
                                  color: isJoined ? Colors.greenAccent : Colors.white, 
                                  fontSize: 12,
                                  fontWeight: isJoined ? FontWeight.bold : FontWeight.normal
                                )
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }
          );
        },
      ),
    );
  }
}
