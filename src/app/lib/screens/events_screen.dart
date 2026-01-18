import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../services/event_service.dart';
import '../services/user_service.dart';
import '../widgets/intent_selection_dialog.dart';
import 'event_learn_more_screen.dart';
import 'package:share_plus/share_plus.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use the EventService to get real events
    final eventService = Provider.of<EventService>(context);
    final events = eventService.events;

    if (events.isEmpty) {
      return const Center(
        child: Text(
          'No upcoming events found.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return _buildEventCard(context, event);
      },
    );
  }

  Widget _buildEventCard(BuildContext context, Event event) {
    final timeStr = DateFormat('HH:mm').format(event.startTime.toLocal());
    final intentStr = event.mostPopularIntent ?? 'Intent';
    final titleStr = event.title;
    final descriptionStr = event.description;

    Widget backgroundWidget;
    if (event.noticeBoardBgImage != null && event.noticeBoardBgImage!.isNotEmpty) {
      backgroundWidget = Image.network(
        event.noticeBoardBgImage!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900),
      );
    } else if (event.noticeBoardBgColor != null && event.noticeBoardBgColor!.isNotEmpty) {
      try {
        String hex = event.noticeBoardBgColor!;
        if (hex.startsWith('#')) hex = hex.substring(1);
        if (hex.length == 6) hex = 'FF$hex';
        backgroundWidget = Container(color: Color(int.parse(hex, radix: 16)));
      } catch (_) {
        backgroundWidget = Container(color: Colors.grey.shade900);
      }
    } else if (event.imageUrl.isNotEmpty) {
      backgroundWidget = Image.network(
        event.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900),
      );
    } else {
      backgroundWidget = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.indigo.shade900,
              Colors.purple.shade900,
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background
          Positioned.fill(
            child: backgroundWidget,
          ),

          // Overlay
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  event.type == EventType.national ? 'National Notice Board' : 'Notice Board',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 24),

                // Next Local Event (Dynamic)
                _buildNoticeItem(
                  icon: Icons.access_time,
                  label: event.type == EventType.global
                      ? 'Worldwide Event'
                      : (event.type == EventType.national ? 'National Event' : 'Local Event'),
                  value: _getEventStatusText(event, timeStr),
                ),
                const SizedBox(height: 16),

                // Event Description / Purpose
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (intentStr != 'Intent' && intentStr.isNotEmpty && descriptionStr.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            intentStr,
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      Text(
                        descriptionStr.isNotEmpty
                            ? descriptionStr
                            : (intentStr != 'Intent' && intentStr.isNotEmpty ? intentStr : 'Join us for a moment of shared intention...'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Participants',
                        NumberFormat.decimalPattern().format(
                          event.participantCount,
                        ),
                        Icons.people,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Manifesting',
                        intentStr != 'Intent' && intentStr.isNotEmpty ? intentStr : 'N/A',
                        Icons.trending_up,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // National Users Stat
                if (event.type == EventType.national)
                  _NationalUserCount(),
                if (event.type == EventType.global)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.public,
                          color: Colors.lightBlueAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${NumberFormat.decimalPattern().format(event.participantCount)} users joined worldwide',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),


                const SizedBox(height: 24),

                // Action Buttons
                if (event.type == EventType.global)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EventLearnMoreScreen(event: event),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.15),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Learn More'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => IntentSelectionDialog(
                                    onIntentSelected: (intent) async {
                                      // Save intent to shared state and register in Firestore
                                      final result = await Provider.of<EventService>(
                                        context,
                                        listen: false, // Don't listen to updates here
                                      ).joinEvent(
                                          event.id, 
                                          event.title, 
                                          intent, 
                                          event.type, 
                                          event.startTime, 
                                          event.endTime,
                                          visibilityAfterMinutes: event.visibilityAfterMinutes ?? 0 // Pass visibility param
                                      );

                                      if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                result.startsWith('Success') 
                                                    ? 'Intent set! (Joined)' 
                                                    : 'Failed: $result',
                                              ),
                                              backgroundColor: result.startsWith('Success') ? Colors.green : Colors.red,
                                              duration: const Duration(seconds: 4), // Longer duration to read
                                            ),
                                          );
                                      }
                                      
                                      // BUG FIX: Delay the overlay trigger to allow dialog to close cleanly
                                      // and prevent "Black Screen" hang.
                                      await Future.delayed(const Duration(milliseconds: 500));

                                      if (context.mounted) {
                                        Provider.of<EventService>(
                                          context,
                                          listen: false,
                                        ).triggerEventFromModel(
                                          event.title,
                                          event.description,
                                          true,
                                          mediaUrl: event.mediaUrl,
                                          intent: intent, // Pass user's intent to overlay
                                        );
                                      }
                                    },
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black87,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Join In',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () {
                             Share.share('Join me for a global peace meditation on Harmony by Intent!'); 
                          },
                          icon: const Icon(
                            Icons.share,
                            color: Colors.white70,
                            size: 18,
                          ),
                          label: const Text(
                            'Invite Friend',
                            style: TextStyle(color: Colors.white70),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (event.type == EventType.national)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => IntentSelectionDialog(
                                    onIntentSelected: (intent) async {
                                      // Save intent to shared state and History
                                      final result = await Provider.of<EventService>(
                                        context,
                                        listen: false,
                                      ).joinEvent(
                                          event.id, 
                                          event.title, 
                                          intent, 
                                          event.type, 
                                          event.startTime, 
                                          event.endTime,
                                          visibilityAfterMinutes: event.visibilityAfterMinutes ?? 0 // Pass visibility param
                                      ); 

                                      if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                result.startsWith('Success') 
                                                    ? 'Intent set! (Joined)' 
                                                    : 'Failed: $result',
                                              ),
                                              backgroundColor: result.startsWith('Success') ? Colors.green : Colors.red,
                                              duration: const Duration(seconds: 4),
                                            ),
                                          );
                                      }
                                    },
                                  ),
                                );
                              },
                              icon: const Icon(Icons.edit_note, size: 18),
                              label: const Text('Add Intent'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amber,
                                side: const BorderSide(color: Colors.amber),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () {
                                // Mock Invite Functionality
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Invite link copied to clipboard! Share it with your friends.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.share,
                                color: Colors.white70,
                                size: 18,
                              ),
                              label: const Text(
                                'Invite Friend',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            // TODO: Implement mute/skip logic
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Event muted')),
                            );
                          },
                          icon: const Icon(
                            Icons.volume_off,
                            size: 16,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            'Mute',
                            style: TextStyle(color: Colors.white70),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeItem({
    required IconData icon,
    required String label,
    required String value,
    String? subValue,
    bool isHighlight = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isHighlight
                ? Colors.amber.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isHighlight ? Colors.amber : Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subValue != null)
                Text(
                  subValue,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _getEventStatusText(Event event, String timeStr) {
    final now = DateTime.now();
    final start = event.startTime.toLocal();
    final end = event.endTime.toLocal();

    if (now.isAfter(start) && now.isBefore(end)) {
      return '$timeStr Today (Active)';
    } else if (now.isAfter(end)) {
      return '$timeStr Today (Ended)';
    }
    return '$timeStr Today';
  }

  // Helper widget for National User Count
  Widget _buildNationalUserCount(BuildContext context) {
      return _NationalUserCount();
  }
}

class _NationalUserCount extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context, listen: false);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('timeZone', isEqualTo: userService.timeZone)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final count = snapshot.data!.docs.length;
        final timeZone = userService.timeZone;

        return Container(
          padding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.public,
                color: Colors.lightBlueAccent,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count National users in $timeZone',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
