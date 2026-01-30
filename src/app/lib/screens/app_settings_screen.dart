import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_service.dart';
import '../services/subscription_service.dart';
import 'personal_information_screen.dart';
import 'support_chat_screen.dart';
import 'subscription_screen.dart'; // Ensure this matches what we have
import '../widgets/gradient_scaffold.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  // Chime settings state
  // bool _worldwideEventsEnabled = true; // Removed local state
  // Representations: 
  // _hourlyChimes[hour][0] = :00
  // _hourlyChimes[hour][1] = :15
  // _hourlyChimes[hour][2] = :30
  // _hourlyChimes[hour][3] = :45
  late List<List<bool>> _hourlyChimes;
  late PageController _chimePageController;
  bool _isLoadingChimes = true;

  @override
  void initState() {
    super.initState();
    _chimePageController = PageController(viewportFraction: 0.9);
    // Initialize with default (all on)
    _hourlyChimes = List.generate(24, (_) => [true, true, true, true]);
    _loadChimeSettings();
  }

  Future<void> _loadChimeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedChimes = prefs.getString('hourly_chimes_matrix');
      
      if (savedChimes != null) {
        final List<dynamic> decoded = jsonDecode(savedChimes);
        setState(() {
          _hourlyChimes = decoded.map<List<bool>>((row) {
            return (row as List).map<bool>((val) => val as bool).toList();
          }).toList();
          _isLoadingChimes = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingChimes = false);
      }
    } catch (e) {
      debugPrint("Error loading chimes: $e");
      if (mounted) setState(() => _isLoadingChimes = false);
    }
  }

  Future<void> _saveChimeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encoded = jsonEncode(_hourlyChimes);
      await prefs.setString('hourly_chimes_matrix', encoded);
    } catch (e) {
      debugPrint("Error saving chimes: $e");
    }
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
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Subscription Section
          _buildSectionHeader('Subscription'),
          Consumer<SubscriptionService>(
            builder: (context, subscriptionService, _) {
              final isSubscribed = subscriptionService.isSubscribed;
              return Card(
                elevation: 2,
                color: Colors.white.withOpacity(0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.stars, color: Colors.amber),
                  title: Text(
                    isSubscribed ? 'Manage Subscription' : 'Upgrade to Harmony Pro', 
                    style: const TextStyle(color: Colors.white)
                  ),
                  subtitle: Text(
                    isSubscribed ? 'Manage your plan and billing' : 'Unlock detailed stats and more', 
                    style: const TextStyle(color: Colors.white70)
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
                  onTap: () async {
                     // 1. Show Loading Indicator
                     showDialog(
                       context: context,
                       barrierDismissible: false,
                       builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
                     );

                     try {
                       if (isSubscribed) {
                         if (context.mounted) Navigator.pop(context);
                         await subscriptionService.showCustomerCenter();
                       } else {
                         // 2. Attempt to show Paywall
                         await subscriptionService.showPaywall();
                         
                         // 3. Remove Loader
                         if (context.mounted) Navigator.pop(context);
                       }
                     } catch (e) {
                       // 4. Handle Errors with a Popup
                       if (context.mounted) {
                         Navigator.pop(context); // Remove loader
                         showDialog(
                           context: context,
                           builder: (context) => AlertDialog(
                             title: const Text("Connection Issue"),
                             content: Text("Details: $e\n\nPlease check your internet connection."),
                             backgroundColor: Colors.grey[900],
                             titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                             contentTextStyle: const TextStyle(color: Colors.white70),
                             actions: [
                               TextButton(
                                 onPressed: () => Navigator.pop(context),
                                 child: const Text("OK", style: TextStyle(color: Colors.amber)),
                               )
                             ],
                           ),
                         );
                       }
                     }
                   },
                ),
              );
            }
          ),
          const SizedBox(height: 24),

          // Personal Information
          _buildSectionHeader('Personal Information'),
          _buildSettingsTile(
            icon: Icons.person,
            title: 'Personal Information',
            subtitle: 'Manage account details',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PersonalInformationScreen()),
              );
            },
          ),
          const SizedBox(height: 24),

          // Chime Settings
          _buildSectionHeader('Chime Configuration'),
          SwitchListTile(
            title: const Text('Global Priority', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Prioritize worldwide events over local chimes', style: TextStyle(color: Colors.white70)),
            value: userService.globalPriority, // Use UserService
            onChanged: (val) => userService.setGlobalPriority(val), // Update UserService
            secondary: const Icon(Icons.public, color: Colors.white70),
            activeColor: Colors.amber,
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Auto-Join Worldwide Events', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Automatically participate in global events (Members Only)', style: TextStyle(color: Colors.white70)),
            value: userService.autoJoinWorldwide, 
            onChanged: (val) {
                 userService.setAutoJoinWorldwide(val);
                 if (val) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auto-Join Enabled: You will automatically join all worldwide events.')));
                 }
            },
            secondary: const Icon(Icons.autorenew, color: Colors.white70),
            activeColor: Colors.amber,
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              userService.eventVolume == 0 ? Icons.volume_off : Icons.volume_up, 
              color: Colors.white70
            ),
            title: const Text('Event Volume', style: TextStyle(color: Colors.white)),
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
                MaterialPageRoute(builder: (context) => const SupportChatScreen()),
              );
            },
          ),
          
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () {
              // Sign Out Logic
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Sign Out'),
          ),
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
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
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
          final hour = hourIndex == 0 ? 12 : (hourIndex > 12 ? hourIndex - 12 : hourIndex);
          final period = hourIndex < 12 ? 'AM' : 'PM';
          final timeLabel = '$hour:00 $period';

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
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
                          _buildChimeSlot(hourIndex, 0, ':00'),
                          _buildChimeSlot(hourIndex, 1, ':15'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildChimeSlot(hourIndex, 2, ':30'),
                          _buildChimeSlot(hourIndex, 3, ':45'),
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

  Widget _buildChimeSlot(int hourIndex, int slotIndex, String label) {
    // If loading, disable interaction slightly or just show default
    if (_isLoadingChimes) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white24)),
      );
    }
    
    final isSelected = _hourlyChimes[hourIndex][slotIndex];
    return GestureDetector(
      onTap: () {
        setState(() {
          _hourlyChimes[hourIndex][slotIndex] = !isSelected;
        });
        _saveChimeSettings();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigoAccent : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.indigoAccent : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
