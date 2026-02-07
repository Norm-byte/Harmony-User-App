import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/gradient_scaffold.dart';
import '../services/user_service.dart';
import '../services/profanity_service.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _messageController = TextEditingController();
  bool _isSending = false;

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    
    // Profanity Check
    if (ProfanityService().hasProfanity(content)) {
      // 1. Notify User (Visual Warning)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profanity detected. Message flagged for review.'),
          backgroundColor: Colors.orange, // Warning color, not error, as it goes to queue
        ),
      );
      
      // 2. Clear Input to reset
      _messageController.clear();
      
      // 3. Send to Moderation Queue (Silent Background Operation)
      final user = UserService();
      try {
        await FirebaseFirestore.instance.collection('moderation_queue').add({
          'content': content,
          'userId': user.userId,
          'userName': user.userName,
          // 'userEmail': user.userEmail, // Removed as not available
          'source': 'Support Chat',
          'timestamp': FieldValue.serverTimestamp(),
          'reason': 'Profanity Detected',
          'status': 'pending', // pending, resolved, rejected
        });
      } catch (e) {
        // Silent fail
      }
      return;
    }

    setState(() => _isSending = true);

    try {
      final user = UserService();
      final batch = FirebaseFirestore.instance.batch();
      
      // 1. Write to user's private message thread
      final userMsgRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.userId)
          .collection('messages')
          .doc();
          
      batch.set(userMsgRef, {
        'content': content,
        'sender': 'user',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'title': 'Support Request',
      });
      
      // 2. Write to Central Support Inbox (Upsert: One entry per user = Threaded View)
      final inboxRef = FirebaseFirestore.instance.collection('support_inbox').doc(user.userId);
      batch.set(inboxRef, {
        'content': content,
        'userId': user.userId,
        'userName': user.userName,
        // 'userEmail': user.userEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'messageId': userMsgRef.id, // Reference to latest message
      }, SetOptions(merge: true));
      
      await batch.commit();

      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = UserService();

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Contact Support'),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Chat List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.userId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        'Support Chat\n\nHow can we help you today? Send us a message.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
                      ),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true, // Show newest at bottom
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index].data() as Map<String, dynamic>;
                    final isUser = msg['sender'] == 'user';
                    final timestamp = (msg['timestamp'] as Timestamp?)?.toDate();

                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.indigo.shade600 : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
                            bottomRight: isUser ? Radius.zero : const Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['content'] ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            if (timestamp != null)
                              Text(
                                DateFormat('h:mm a').format(timestamp),
                                style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black.withOpacity(0.2),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, color: Colors.amber),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
