import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/event_service.dart';
import '../services/user_service.dart';
import '../services/profanity_service.dart'; // Added missing import
import '../widgets/gradient_scaffold.dart';

class ChatScreen extends StatefulWidget {
  final String eventTitle;
  final String? groupId; // If provided, connects to a specific Firestore group

  const ChatScreen({super.key, required this.eventTitle, this.groupId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _intentController = TextEditingController();
  
  // Daily Message Limit State
  int _messagesRemaining = 50;
  final int _maxDailyMessages = 50;
  
  // Maintenance Mode (Mock - controlled by backend in real app)
  final bool _isMaintenanceMode = false;
  
  // Real Firestore backend for messages if groupId is present
  Stream<QuerySnapshot>? _messagesStream;
  String? _resolvedGroupId; // Resolved dynamically if initially null

  @override
  void initState() {
    super.initState();
    _loadDailyLimit();
    _resolvedGroupId = widget.groupId;
    
    if (_resolvedGroupId != null) {
      _initFirestoreStream();
    } else {
      _resolveGroupByName();
    }
  }

  void _initFirestoreStream() {
      if (_resolvedGroupId == null) return;
      
      _messagesStream = FirebaseFirestore.instance
          .collection('community_groups')
          .doc(_resolvedGroupId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots();
      
      // Force rebuild to show stream
      if (mounted) setState(() {});
  }

  Future<void> _toggleLike(String messageId, List<dynamic> likedBy, List<dynamic> dislikedBy, bool isLike) async {
      if (_resolvedGroupId == null) return;
      
      final uid = UserService().userId;
      if (uid.isEmpty) return;

      final docRef = FirebaseFirestore.instance
          .collection('community_groups')
          .doc(_resolvedGroupId)
          .collection('messages')
          .doc(messageId);
      
      if (isLike) {
         if (likedBy.contains(uid)) {
            // Unlike
            await docRef.update({
               'likes': FieldValue.increment(-1),
               'likedBy': FieldValue.arrayRemove([uid])
            });
         } else {
            // Like
             await docRef.update({
               'likes': FieldValue.increment(1),
               'likedBy': FieldValue.arrayUnion([uid]),
               'dislikes': dislikedBy.contains(uid) ? FieldValue.increment(-1) : FieldValue.increment(0),
               'dislikedBy': FieldValue.arrayRemove([uid])
            });
         }
      } else {
         // Dislike logic
          if (dislikedBy.contains(uid)) {
            // Remove Dislike
            await docRef.update({
               'dislikes': FieldValue.increment(-1),
               'dislikedBy': FieldValue.arrayRemove([uid])
            });
         } else {
            // Dislike
             await docRef.update({
               'dislikes': FieldValue.increment(1),
               'dislikedBy': FieldValue.arrayUnion([uid]),
               'likes': likedBy.contains(uid) ? FieldValue.increment(-1) : FieldValue.increment(0),
               'likedBy': FieldValue.arrayRemove([uid])
            });
         }
      }
  }

  Future<void> _resolveGroupByName() async {
    // Attempt to find group by name validation
    try {
      final query = await FirebaseFirestore.instance
          .collection('community_groups')
          .where('name', isEqualTo: widget.eventTitle)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        if (mounted) {
           setState(() {
             _resolvedGroupId = query.docs.first.id;
             _initFirestoreStream();
           });
           debugPrint('ChatScreen resolved group ID: $_resolvedGroupId');
        }
      } else {
        debugPrint('ChatScreen: Could not find group for ${widget.eventTitle}');
      }
    } catch (e) {
      debugPrint('ChatScreen resolution error: $e');
    }
  }

  Future<void> _loadDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final lastResetStr = prefs.getString('chat_daily_limit_date');
    final todayStr = DateTime.now().toIso8601String().split('T').first;

    if (lastResetStr != todayStr) {
      // New day, reset
      setState(() {
        _messagesRemaining = _maxDailyMessages;
      });
      await prefs.setString('chat_daily_limit_date', todayStr);
      await prefs.setInt('chat_messages_remaining', _maxDailyMessages);
    } else {
      setState(() {
        _messagesRemaining = prefs.getInt('chat_messages_remaining') ?? _maxDailyMessages;
      });
    }
  }

  // Mock Admin Settings (Removed)
  // final bool _showSystemMessage = true;
  // final String _systemMessage = 'Welcome to the chat for this event. Please be respectful.';
  // String _userIntent = ''; // Removed in favor of EventService

  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'Alice',
      'text': 'Hello everyone! Excited to be here.',
      'isMe': false,
      'time': '10:05 AM',
      'location': 'New York, USA',
      'timezone': 'EST'
    },
    {
      'sender': 'Bob',
      'text': 'Greetings from London!',
      'isMe': false,
      'time': '10:06 AM',
      'location': 'London, UK',
      'timezone': 'GMT'
    },
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _intentController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (ProfanityService().hasProfanity(text)) {
      final userService = UserService();
      // Send to moderation queue instead of blocking silently
      await FirebaseFirestore.instance.collection('moderation_queue').add({
         'content': text,
         'userId': userService.userId,
         'userName': userService.userName,
         'source': 'Chat Room (${widget.eventTitle})',
         'timestamp': FieldValue.serverTimestamp(),
         'reason': 'Profanity Detected',
         'status': 'pending',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profanity detected. Message sent for moderation.'),
          backgroundColor: Colors.orange,
        ),
      );
      // Clear text so user can't retry immediately? 
      // User requested "user gets sent straight to moderation queue". 
      // We interpret this as "their message goes to queue".
      _messageController.clear(); 
      return;
    }
    
    // Check limit
    if (_messagesRemaining <= 0) {
      _showUpgradeDialog();
      return;
    }

    if (_resolvedGroupId != null) {
      // Send to Firestore
      try {
        final userService = UserService(); // Use singleton
        String senderName = userService.userName;
        String senderId = userService.userId;
        
        await FirebaseFirestore.instance
            .collection('community_groups')
            .doc(_resolvedGroupId)
            .collection('messages')
            .add({
              'text': text,
              'sender': senderName,
              'userId': senderId, // For admin moderation
              'isMe': true, // Logic handled in UI
              'timestamp': FieldValue.serverTimestamp(),
              'location': 'Unknown',
              'timezone': userService.timeZone,
            });
            
        setState(() {
           _messageController.clear();
           _messagesRemaining--;
        });
      } catch (e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending: $e')));
      }
    } else {
        // Fallback to local mock for non-group events (legacy)
        setState(() {
          _messages.add({
            'sender': 'Me',
            'text': text,
            'isMe': true,
            'time': 'Now',
            'location': 'Unknown',
            'timezone': 'Local',
          });
          _messageController.clear();
          _messagesRemaining--;
        });
    }
    
    // Persist new remaining count
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('chat_messages_remaining', _messagesRemaining);
    });
  }

  void _showUpgradeDialog() {
    final bool isLimitReached = _messagesRemaining <= 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isLimitReached ? 'Daily Limit Reached' : 'Messages Remaining'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(
                    isLimitReached 
                    ? 'You have used all your free messages for today.' 
                    : 'You have $_messagesRemaining messages left for today.'
                ),
                const SizedBox(height: 16),
                const Text('Expand to Unlimited?', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Upgrade to Harmony Premium to get unlimited messages, exclusive content, and more.'),
            ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
               Navigator.pop(context);
               // Navigate to subscription screen
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Redirecting to Premium Upgrade...'))
               );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            child: const Text('Get Unlimited'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isMaintenanceMode) {
      return GradientScaffold(
        appBar: AppBar(title: Text('Chat: ${widget.eventTitle}'), foregroundColor: Colors.white),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.construction, size: 64, color: Colors.amber),
              const SizedBox(height: 16),
              const Text('Chat Closed for Maintenance', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Please check back later.', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    return GradientScaffold(
      appBar: AppBar(
        title: Text('Chat: ${widget.eventTitle}'),
        // backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Sticky System Message (Real Data)
          StreamBuilder<DocumentSnapshot>(
            stream: _resolvedGroupId != null
                ? FirebaseFirestore.instance.collection('community_groups').doc(_resolvedGroupId).snapshots()
                : FirebaseFirestore.instance.collection('app_config').doc('community_settings').snapshots(), // Fallback or global?
            builder: (context, snapshot) {
               if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
               
               final data = snapshot.data!.data() as Map<String, dynamic>;
               String? adminMessage;
               
               if (_resolvedGroupId != null) {
                 adminMessage = data['adminMessage'] as String?;
               } else {
                 // If displaying a non-group event (unlikely now), use global
                 // adminMessage = data['admin_message'];
               }

               // Fallback default message
               final displayMessage = (adminMessage != null && adminMessage.isNotEmpty) 
                   ? adminMessage 
                   : "Welcome to the community! Please share your thoughts respectfully.";

               return Container(
                margin: const EdgeInsets.all(12), // Added margin to match Feed style
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade900.withOpacity(0.9), // Darker, more prominent
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.5)),
                   boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.amber,
                          child: Icon(Icons.shield, size: 14, color: Colors.black),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Admin Message',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                         const Spacer(),
                        Icon(Icons.push_pin, size: 16, color: Colors.white.withOpacity(0.5)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displayMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              );
            }
          ),

          if (_resolvedGroupId != null)
             Expanded(
               child: StreamBuilder<QuerySnapshot>(
                 stream: _messagesStream,
                 builder: (context, snapshot) {
                   if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
                   if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
                   
                   final docs = snapshot.data!.docs;
                   
                   return ListView.builder(
                     reverse: true, // Chat usually bottom-up
                     padding: const EdgeInsets.all(16),
                     itemCount: docs.length,
                     itemBuilder: (context, index) {
                       final data = docs[index].data() as Map<String, dynamic>;
                       final isMe = data['sender'] == 'Me' || (data['isMe'] == true) || (data['userId'] == UserService().userId); 
                       final text = data['text'] ?? '';
                       final sender = data['sender'] ?? 'User';
                       final likedBy = List<String>.from(data['likedBy'] ?? []);
                       final dislikedBy = List<String>.from(data['dislikedBy'] ?? []);
                       final likes = data['likes'] ?? 0;
                       final docId = docs[index].id;
                       
                       return Align(
                         alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                         child: Container(
                           margin: const EdgeInsets.only(bottom: 12),
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                           constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                           decoration: BoxDecoration(
                             color: isMe ? Colors.indigo : Colors.white.withOpacity(0.1),
                             borderRadius: BorderRadius.only(
                               topLeft: const Radius.circular(12),
                               topRight: const Radius.circular(12),
                               bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                               bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                             ),
                           ),
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               if (!isMe)
                                 Text(
                                   sender,
                                   style: const TextStyle(
                                     fontSize: 12,
                                     fontWeight: FontWeight.bold,
                                     color: Colors.amber, 
                                   ),
                                 ),
                               if (!isMe) const SizedBox(height: 4),
                               Text(
                                 text,
                                 style: const TextStyle(color: Colors.white),
                               ),
                               const SizedBox(height: 4),
                               Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Thumbs Up
                                    InkWell(
                                      onTap: () => _toggleLike(docId, likedBy, dislikedBy, true),
                                      child: Row(
                                        children: [
                                          Icon(
                                            likedBy.contains(UserService().userId) ? Icons.thumb_up : Icons.thumb_up_outlined, 
                                            size: 14, 
                                            color: likedBy.contains(UserService().userId) ? Colors.greenAccent : Colors.white38
                                          ),
                                          if (likes > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(left: 4),
                                              child: Text('$likes', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Thumbs Down
                                    InkWell(
                                      onTap: () => _toggleLike(docId, likedBy, dislikedBy, false),
                                      child: Icon(
                                        dislikedBy.contains(UserService().userId) ? Icons.thumb_down : Icons.thumb_down_outlined, 
                                        size: 14, 
                                        color: dislikedBy.contains(UserService().userId) ? Colors.redAccent : Colors.white38
                                      ),
                                    ),
                                  ],
                                ),
                             ],
                           ),
                         ),
                       );
                     },
                   );
                 }
               ),
             )
          else
            Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['isMe'] as bool;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.indigo : Colors.white.withOpacity(0.1), // Changed for dark theme
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                        bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                msg['sender'],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber, // Changed for visibility
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${msg['location']} (${msg['timezone']})',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70, // Changed for visibility
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        if (!isMe) const SizedBox(height: 4),
                        Text(
                          msg['text'],
                          style: const TextStyle(
                            color: Colors.white, // Always white text
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              msg['time'],
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Thumbs Up
                            InkWell(
                              onTap: () {
                                  // Local mock toggle
                                  setState(() {
                                    msg['liked'] = !(msg['liked'] ?? false);
                                  });
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.thumb_up, 
                                    size: 14, 
                                    color: (msg['liked'] ?? false) ? Colors.greenAccent : Colors.white38
                                  ),
                                  if (msg['likes'] != null && msg['likes'] > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Text('${msg['likes']}', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Thumbs Down
                            InkWell(
                              onTap: () {
                                setState(() {
                                  msg['disliked'] = !(msg['disliked'] ?? false);
                                  msg['liked'] = false; // Toggle
                                });
                              },
                              child: Icon(
                                Icons.thumb_down, 
                                size: 14, 
                                color: (msg['disliked'] ?? false) ? Colors.redAccent : Colors.white38
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
          ),

          // Sticky User Intent Section (Connected to Shared State)
          if (widget.eventTitle.toLowerCase().contains('global') || widget.eventTitle.toLowerCase().contains('worldwide'))
          Consumer<EventService>(
            builder: (context, eventService, _) {
              final userIntent = eventService.userIntent;
              
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade900.withOpacity(0.6),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.1)),
                    bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Intent',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (userIntent.isEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _intentController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Set your intent for this event...',
                                hintStyle: TextStyle(color: Colors.white38),
                                isDense: true,
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () {
                              if (_intentController.text.isNotEmpty) {
                                eventService.setUserIntent(_intentController.text);
                                _intentController.clear();
                              }
                            },
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              userIntent,
                              style: const TextStyle(
                                color: Colors.white,
                                fontStyle: FontStyle.italic,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
                            onPressed: () {
                              _intentController.text = userIntent;
                              eventService.setUserIntent('');
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3), // Darker input area
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  offset: const Offset(0, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.white70),
                  onPressed: () {},
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                InkWell(
                  onTap: () => _showUpgradeDialog(),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _messagesRemaining <= 10 ? Colors.red.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _messagesRemaining <= 10 ? Colors.red.withOpacity(0.5) : Colors.white24,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bolt, 
                          size: 14, 
                          color: _messagesRemaining <= 10 ? Colors.redAccent : Colors.amber
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_messagesRemaining left',
                          style: TextStyle(
                            color: _messagesRemaining <= 10 ? Colors.redAccent : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.amber),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
