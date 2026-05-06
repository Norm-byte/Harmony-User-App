import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/event_service.dart';
import 'support_chat_screen.dart';
import '../widgets/gradient_scaffold.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late PageController _chimePageController;

  @override
  void initState() {
    super.initState();
    _chimePageController = PageController(viewportFraction: 0.9);
  }

  @override
  void dispose() {
    _chimePageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context);

    // Use GradientScaffold since this is a new full screen
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Chime Settings'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Chime Settings
          _buildSectionHeader('Chime Configuration'),
          SwitchListTile(
            title: const Text(
              'Global Priority',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Prioritize worldwide events over local chimes',
              style: TextStyle(color: Colors.white70),
            ),
            value: userService.globalPriority, // Use UserService
            onChanged: (val) =>
                userService.setGlobalPriority(val), // Update UserService
            secondary: const Icon(Icons.public, color: Colors.white70),
            activeThumbColor: Colors.amber,
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text(
              'Auto-Join Worldwide Events',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Automatically participate in global events (Members Only)',
              style: TextStyle(color: Colors.white70),
            ),
            value: userService.autoJoinWorldwide,
            onChanged: (val) {
              userService.setAutoJoinWorldwide(val);
              if (val) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Auto-Join Enabled: You will automatically join all worldwide events.',
                    ),
                  ),
                );
              }
            },
            secondary: const Icon(Icons.autorenew, color: Colors.white70),
            activeThumbColor: Colors.amber,
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              userService.eventVolume == 0 ? Icons.volume_off : Icons.volume_up,
              color: Colors.white70,
            ),
            title: const Text(
              'Event Volume',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Slider(
              value: userService.eventVolume,
              onChanged: (val) => userService.setEventVolume(val),
              activeColor: Colors.amber,
              inactiveColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Hourly Chime Slots',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _build24HourChimeSelector(),
          const SizedBox(height: 10),
          _buildChimeLegend(),
          const SizedBox(height: 24),

          // Community & Support
          _buildSectionHeader('Community & Support'),
          _buildSettingsTile(
            icon: Icons.support_agent,
            title: 'Contact Support',
            subtitle: 'Get help or send feedback',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SupportChatScreen(),
                ),
              );
            },
          ),
          _buildSettingsTile(
            icon: Icons.notifications_active,
            title: 'Notification Health Check',
            subtitle: 'Verify permission and queued reminders',
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final notificationService = NotificationService();
              final granted = await notificationService
                  .requestNotificationPermission();

              await notificationService.syncDormantPlaybackReminders(
                events: EventService().events,
                userService: userService,
              );

              final debug = await notificationService.getNotificationDebugState();
              if (!mounted) return;

              final status = debug['authorizationStatus'] ?? 'unknown';
              final pendingDormant = debug['pendingDormant'] ?? 0;

              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Notifications: ${granted ? 'granted' : 'not granted'} '
                    '(status=$status), dormant pending=$pendingDormant',
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            },
          ),

          if (Platform.isAndroid) ...[  
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              color: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text(
                        'Dormant Device Override',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Keep Harmony Chimes active whilst your phone is idle.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      value: userService.dormantPlaybackEnabled,
                      onChanged: (value) async {
                        await userService.setDormantPlaybackEnabled(value);

                        if (value) {
                          var probeArmed = false;

                          try {
                            await NotificationService().syncDormantPlaybackReminders(
                              events: EventService().events,
                              userService: userService,
                            );
                          } catch (e) {
                            debugPrint('Dormant sync on toggle failed: $e');
                          }

                          try {
                            probeArmed = await NotificationService()
                                .scheduleNativeDebugProbe(delaySeconds: 15);
                          } catch (e) {
                            debugPrint('Dormant debug probe on toggle failed: $e');
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  probeArmed
                                      ? 'Dormant probe armed. Lock now and wait 20 seconds.'
                                      : 'Dormant enabled. Probe arm failed; scheduling still attempted.',
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        } else {
                          await NotificationService().cancelDormantPlaybackReminders();
                        }

                        if (!context.mounted) return;
                        if (value) {
                          _showDormantPlaybackSetup(context, userService);
                        }
                      },
                      activeThumbColor: Colors.amber,
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                        Icons.bedtime_outlined,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Build marker: 28 Mar 00:05',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.white54,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _build24HourChimeSelector() {
    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller: _chimePageController,
        itemCount: 24,
        itemBuilder: (context, hourIndex) {
          final userService = context.watch<UserService>();
          final hour = hourIndex == 0
              ? 12
              : (hourIndex > 12 ? hourIndex - 12 : hourIndex);
          final period = hourIndex < 12 ? 'AM' : 'PM';
          final timeLabel = '$hour:00 $period';

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  timeLabel,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildChimeSlot(userService, hourIndex, 0, ':00'),
                          _buildChimeSlot(userService, hourIndex, 1, ':15'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildChimeSlot(userService, hourIndex, 2, ':30'),
                          _buildChimeSlot(userService, hourIndex, 3, ':45'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChimeSlot(
    UserService userService,
    int hourIndex,
    int slotIndex,
    String label,
  ) {
    if (!userService.settingsLoaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white24)),
      );
    }

    final state = userService.getChimeSlotState(hourIndex, slotIndex);
    // 0 = video (indigo), 1 = audio (amber), 2 = off (grey)
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final IconData? icon;

    switch (state) {
      case 1:
        bgColor = Colors.amber;
        borderColor = Colors.amber;
        textColor = Colors.black87;
        icon = Icons.volume_up_rounded;
        break;
      case 2:
        bgColor = Colors.white.withValues(alpha: 0.04);
        borderColor = Colors.white.withValues(alpha: 0.08);
        textColor = Colors.white30;
        icon = null;
        break;
      default: // 0 = video
        bgColor = Colors.indigoAccent;
        borderColor = Colors.indigoAccent;
        textColor = Colors.white;
        icon = Icons.play_circle_filled_rounded;
    }

    return GestureDetector(
      onTap: () => userService.cycleChimeSlot(hourIndex, slotIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: textColor), const SizedBox(width: 4)],
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChimeLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _legendChip(Colors.indigoAccent, Icons.play_circle_filled_rounded),
          const SizedBox(width: 4),
          const Text('Video', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 14),
          _legendChip(Colors.amber, Icons.volume_up_rounded),
          const SizedBox(width: 4),
          const Text('Audio', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 14),
          _legendChip(Colors.white24, null),
          const SizedBox(width: 4),
          const Text('Off  —  tap to cycle', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _legendChip(Color color, IconData? icon) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: icon != null ? Icon(icon, size: 13, color: Colors.white) : null,
    );
  }

  void _showDormantPlaybackSetup(
    BuildContext context,
    UserService userService,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dormant Device Setup',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'These options help Harmony deliver your chimes while your phone is dormant. Your paused hourly slots still stay paused.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.notifications_active,
                    color: Colors.amber,
                  ),
                  title: const Text(
                    'Allow notifications',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Needed so Harmony can alert your device at the right time.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () =>
                      NotificationService().requestNotificationPermission(),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.alarm, color: Colors.amber),
                  title: const Text(
                    'Allow exact alarms',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Helps your hourly chimes fire on time while the phone is inactive.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () => NotificationService().openExactAlarmSettings(),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.battery_saver, color: Colors.amber),
                  title: const Text(
                    'Battery unrestricted',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Helps stop Android from silencing Harmony while the phone is dormant.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () =>
                      NotificationService().openBatteryOptimizationSettings(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}
