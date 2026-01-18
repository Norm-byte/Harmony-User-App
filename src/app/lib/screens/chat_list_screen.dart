import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/group_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GroupService>(
      builder: (context, groupService, _) {
        final myGroups = groupService.myGroups;

        if (myGroups.isEmpty) {
          return const Center(
            child: Text(
              'You haven\'t joined any groups yet.\nVisit the "Groups" tab to find one!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return ListView.builder(
          itemCount: myGroups.length,
          itemBuilder: (context, index) {
            final group = myGroups[index];
            final title = group['name'] ?? 'Unknown Group';
            // Use description or a placeholder if no last message functionality yet
            final lastMessage = group['description'] ?? 'Tap to chat...'; 
            
            return Card( // Wrapped in Card for better visibility on gradient
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white.withOpacity(0.1),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: group['colorValue'] != null 
                      ? Color(group['colorValue']).withOpacity(0.2) 
                      : Colors.indigo.shade100,
                  child: Icon(
                    group['iconCode'] != null 
                        ? IconData(group['iconCode'], fontFamily: 'MaterialIcons') 
                        : Icons.chat_bubble_outline,
                    color: group['colorValue'] != null 
                        ? Color(group['colorValue']) 
                        : Colors.indigo.shade700
                  ),
                ),
                title: Text(title, style: const TextStyle(color: Colors.white)),
                subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white60, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        eventTitle: title,
                        groupId: group['id'], // Pass the Firestore ID to enable real chat
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
}
