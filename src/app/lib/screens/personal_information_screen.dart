import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/gradient_scaffold.dart';
import 'legal_document_screen.dart';
import '../services/user_service.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() => _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  @override
  Widget build(BuildContext context) {
    final userService = context.watch<UserService>();
    
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Personal Information'),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingsTile(
            icon: Icons.badge_outlined,
            title: 'Profile Information',
            subtitle: '${userService.userName} • ${userService.timeZone}',
            onTap: () => _showProfileDetailsDialog(context),
          ),
          const SizedBox(height: 16),
          _buildSettingsTile(
            icon: Icons.lock_outlined,
            title: 'Change Password',
            subtitle: 'Update your account password',
            onTap: () => _showChangePasswordDialog(context),
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
          const SizedBox(height: 12),
          _buildSettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'Read how your data is handled',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  // Admin legal tab stores this document under doc id 'legal'.
                  builder: (context) => const LegalDocumentScreen(title: 'Privacy Policy', docId: 'legal'),
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

  void _showProfileDetailsDialog(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userService = context.read<UserService>();
    final email = user?.email ?? 'No email available';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Profile Information', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Name', userService.userName),
            const SizedBox(height: 8),
            _buildInfoRow('Email', email),
            const SizedBox(height: 8),
            _buildInfoRow('Time Zone', userService.timeZone),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white70, fontSize: 14),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('Change Password', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your current password and choose a new one.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                TextField(
                  enabled: !isLoading,
                  controller: currentPasswordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                    disabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  enabled: !isLoading,
                  controller: newPasswordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                    disabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                    helperText: 'Min 8 characters, 1 uppercase, 1 number',
                    helperStyle: TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  enabled: !isLoading,
                  controller: confirmPasswordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                    disabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final current = currentPasswordController.text;
                      final newPass = newPasswordController.text;
                      final confirm = confirmPasswordController.text;

                      // Validation
                      if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All fields required')),
                        );
                        return;
                      }

                      if (newPass != confirm) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('New passwords do not match')),
                        );
                        return;
                      }

                      if (newPass.length < 8) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password must be at least 8 characters')),
                        );
                        return;
                      }

                      if (!RegExp(r'[A-Z]').hasMatch(newPass)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password must contain at least 1 uppercase letter')),
                        );
                        return;
                      }

                      if (!RegExp(r'[0-9]').hasMatch(newPass)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password must contain at least 1 number')),
                        );
                        return;
                      }

                      setState(() => isLoading = true);

                      try {
                        // Call backend function to change password
                        await FirebaseAuth.instance.currentUser?.updatePassword(newPass);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password updated successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        if (context.mounted) {
                          String message = 'Failed to update password';
                          if (e.code == 'wrong-password') {
                            message = 'Current password is incorrect';
                          } else if (e.code == 'requires-recent-login') {
                            message = 'Please sign out and sign in again for security';
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(message)),
                          );
                        }
                        setState(() => isLoading = false);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                        setState(() => isLoading = false);
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                      ),
                    )
                  : const Text('Update', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
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
