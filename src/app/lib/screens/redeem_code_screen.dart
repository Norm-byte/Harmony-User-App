import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../widgets/gradient_scaffold.dart';
import '../services/subscription_service.dart';
import 'home_screen.dart';

class RedeemCodeScreen extends StatefulWidget {
  const RedeemCodeScreen({super.key});

  @override
  State<RedeemCodeScreen> createState() => _RedeemCodeScreenState();
}

class _RedeemCodeScreenState extends State<RedeemCodeScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _redeemCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please log in before redeeming a VIP code.';
        });
        return;
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('vip_codes')
          .where('code', isEqualTo: code)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        setState(() {
          _errorMessage = 'Invalid or expired code.';
          _isLoading = false;
        });
        return;
      }

      final doc = querySnapshot.docs.first;
      final data = doc.data();
      
      // Check if this is a Super Admin code (permanent)
      final isSuperAdmin = data['type'] == 'super_admin';

      if (!isSuperAdmin) {
        // Mark as redeemed only if it's a standard one-time code
        await doc.reference.update({
          'status': 'redeemed',
          'redeemedAt': FieldValue.serverTimestamp(),
          'redeemedBy': currentUser.uid,
        });
      }

      final subService = Provider.of<SubscriptionService>(context, listen: false);
      await subService.setVipStatus(true);

      // Persist isVip in Firestore under the authenticated user's UID so the
      // login path detects VIP status on future sign-ins.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
            'isVip': true,
            'isSuperAdmin': isSuperAdmin,
          }, SetOptions(merge: true));

      if (mounted) {
        // Show success and navigate
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isSuperAdmin 
                ? 'Super Admin Access Granted!' 
                : 'Code redeemed successfully! Welcome aboard.'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigate to Home Screen
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (_) => HomeScreen(isSuperAdmin: isSuperAdmin)),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Redeem VIP Code', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your access code',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the 8-character code shared with you to unlock full access.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'VIP Code',
                labelStyle: const TextStyle(color: Colors.white70),
                hintText: 'XXXX-XXXX',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white30),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
                errorText: _errorMessage,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                prefixIcon: const Icon(Icons.vpn_key, color: Colors.white70),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _redeemCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.indigo.shade900,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Redeem Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
