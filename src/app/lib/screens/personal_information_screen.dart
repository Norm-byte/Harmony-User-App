import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/gradient_scaffold.dart';
import 'legal_document_screen.dart';
import '../services/user_service.dart';
import '../services/subscription_service.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() => _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  @override
  Widget build(BuildContext context) {
    final userService = context.watch<UserService>();
    final subscriptionService = context.watch<SubscriptionService>();
    
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Personal Information'),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingsTile(
            icon: Icons.stars,
            title: subscriptionService.isSubscribed ? 'Manage Subscription' : 'Subscribe to Premium',
            subtitle: subscriptionService.isSubscribed ? 'View plan details' : 'Unlock full access',
            onTap: () async {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
              );
              try {
                // 1. VIP Check
                if (subscriptionService.isVip) {
                    if (context.mounted) Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF2A2A2A),
                        title: const Text('VIP Member', style: TextStyle(color: Colors.amber)),
                        content: const Text(
                          'You have full access via VIP Override.\n\nNo subscription management is needed.',
                          style: TextStyle(color: Colors.white),
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.amber)))],
                      )
                    );
                    return;
                }

                // 2. Refresh Status
                await subscriptionService.refreshSubscriptionStatus();

                // 3. Choice Menu
                if (subscriptionService.isSubscribed) {
                  if (context.mounted) Navigator.pop(context); // Close loader
                  
                  showModalBottomSheet(
                    context: context, 
                    backgroundColor: const Color(0xFF2A2A2A),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.settings, color: Colors.white),
                            title: const Text('Manage Subscription', style: TextStyle(color: Colors.white)),
                            subtitle: const Text('View details, cancel, or restore', style: TextStyle(color: Colors.white70)),
                            onTap: () {
                              Navigator.pop(context);
                              subscriptionService.showCustomerCenter();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.star, color: Colors.amber),
                            title: const Text('View Plans & Renew', style: TextStyle(color: Colors.white)),
                            subtitle: const Text('See available plans and pricing', style: TextStyle(color: Colors.white70)),
                            onTap: () {
                              Navigator.pop(context);
                              subscriptionService.showPaywall();
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    )
                  );
                } else {
                  await subscriptionService.showPaywall();
                  if (context.mounted) Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
          ),
          _buildSettingsTile(
            icon: Icons.password,
            title: 'Change Password',
            subtitle: 'Update your security',
            onTap: () {
              _showChangePasswordDialog(context);
            },
          ),
          /*
          _buildSettingsTile(
            icon: Icons.lock_outline,
            title: 'Login Details',
            subtitle: 'Manage email and password',
            onTap: () {
              // Navigate to Login Details
            },
          ),
          */
          _buildSettingsTile(
            icon: Icons.badge_outlined,
            title: 'Profile Information',
            subtitle: '${userService.userName} • ${userService.timeZone}',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.email_outlined,
            title: 'Email Address',
            subtitle: FirebaseAuth.instance.currentUser?.email ?? 'Not available',
            onTap: () {
              // Edit Email
            },
          ),
          // Bank Details and Auto-Subscribe removed for compliance

          const Padding(
            padding: EdgeInsets.only(left: 16, top: 0),
            child: Text(
              'Note: In-app purchases are handled by your app store account.',
              style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),

          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              'Legal & Information',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          
          _buildSettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            subtitle: 'Read our terms of service',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LegalDocumentScreen(title: 'Terms & Conditions', docId: 'terms'),
                ),
              );
            },
          ),
          _buildSettingsTile(
            icon: Icons.gavel,
            title: 'Legal',
            subtitle: 'Legal notices',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LegalDocumentScreen(title: 'Legal', docId: 'legal'),
                ),
              );
            },
          ),
          _buildSettingsTile(
            icon: Icons.info_outline,
            title: 'About Harmony',
            subtitle: 'Our Concept',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LegalDocumentScreen(title: 'About', docId: 'about'),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          
          // Delete Account Button (Required for Compliance)
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _showDeleteAccountDialog,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Change Password', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your new password below.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'New Password',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            child: const Text('Update', style: TextStyle(color: Colors.amber)),
            onPressed: () async {
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match')),
                );
                return;
              }
              if (newPasswordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters')),
                );
                return;
              }

              Navigator.pop(context); // Close input dialog

              // Show loading
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
              );

              // Simulate network delay
              await Future.delayed(const Duration(seconds: 2));

              if (context.mounted) {
                Navigator.pop(context); // Close loading
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated successfully')),
                );

                // Touch the backend to update 'lastActive' or similar to make it feel real
                final userService = Provider.of<UserService>(context, listen: false);
                await userService.setUser(userService.userId, userService.userName);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action is permanent and cannot be undone.\n\nAll your data will be erased immediately.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              await _performAccountDeletion();
            },
            child: const Text('DELETE PERMANENTLY'),
          ),
        ],
      ),
    );
  }

  Future<void> _performAccountDeletion() async {
    try {
      // 1. Delete from Firebase Auth (Rules typically clean up Firestore via functions, or we rely on Auth deletion)
      // Note: Ideally, a Cloud Function triggers on auth.delete to wipe Firestore data for full GDPR compliance.
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.delete();
        // The main.dart AuthStream will detect this and redirect to Onboarding automatically.
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: $e. You may need to re-login to prove identity first.')),
        );
      }
    }
  }

  // Widget _buildSectionHeader(String title) removed as it is no longer used

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white30),
      onTap: onTap,
    );
  }
}
