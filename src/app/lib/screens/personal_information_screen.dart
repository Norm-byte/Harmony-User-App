import 'package:flutter/material.dart';
import '../widgets/gradient_scaffold.dart';
import 'legal_document_screen.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() => _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  bool _autoSubscribe = true;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Personal Information'),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingsTile(
            icon: Icons.lock_outline,
            title: 'Login Details',
            subtitle: 'Manage email and password',
            onTap: () {
              // Navigate to Login Details
            },
          ),
          _buildSettingsTile(
            icon: Icons.password,
            title: 'Change Password',
            subtitle: 'Update your security',
            onTap: () {
              // Navigate to Change Password
            },
          ),
          _buildSettingsTile(
            icon: Icons.badge_outlined,
            title: 'Profile Information',
            subtitle: 'Name, Location, Timezone',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.email_outlined,
            title: 'Email Address',
            subtitle: 'user@example.com',
            onTap: () {
              // Edit Email
            },
          ),
          _buildSettingsTile(
            icon: Icons.account_balance_outlined,
            title: 'Bank Details',
            subtitle: 'Manage payment methods',
            onTap: () {
              // Edit Bank Details
            },
          ),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: const Icon(Icons.subscriptions_outlined, color: Colors.white70),
            title: const Text('Auto-Subscribe', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Automatically renew subscription payment', style: TextStyle(color: Colors.white54)),
            trailing: Transform.scale(
              scale: 0.8,
              child: Switch(
                value: _autoSubscribe,
                onChanged: (val) => setState(() => _autoSubscribe = val),
                activeThumbColor: Colors.white,
                activeTrackColor: Colors.white24,
                inactiveThumbColor: Colors.white54,
                inactiveTrackColor: Colors.white10,
              ),
            ),
            onTap: () => setState(() => _autoSubscribe = !_autoSubscribe),
          ),

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
            subtitle: 'App info and legal',
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
        ],
      ),
    );
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
