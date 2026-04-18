import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/gradient_scaffold.dart';
import '../services/user_service.dart';
import '../services/subscription_service.dart';
import 'package:provider/provider.dart';
import 'home_screen.dart';
import 'subscription_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    debugPrint('HARMONY_LOGIN_START: email=${_emailController.text.trim()} passwordLen=${_passwordController.text.length}');
    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = credential.user!;
      debugPrint('HARMONY_LOGIN_AUTH_OK: uid=${user.uid} email=${user.email}');
      final displayName = user.displayName ?? user.email ?? 'Member';
      await UserService().setUser(user.uid, displayName);

      if (!mounted) return;

      final subService = Provider.of<SubscriptionService>(
        context,
        listen: false,
      );

      // Stage 1: Sync VIP from Firestore user doc.
      // Firebase Auth is now signed in so refreshVipFromAuthUser() is reliable.
      await subService.refreshVipFromAuthUser();
      debugPrint('HARMONY_LOGIN_AFTER_SYNC: isVip=${subService.isVip}');

      // Read isSuperAdmin from the user document (written during sign-up/redeem).
      bool isSuperAdmin = false;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        isSuperAdmin = userDoc.data()?['isSuperAdmin'] == true;
        debugPrint('HARMONY_LOGIN_USERDOC: isVip=${userDoc.data()?['isVip']} isSuperAdmin=$isSuperAdmin');
      } catch (e) {
        debugPrint('HARMONY_LOGIN_USERDOC_ERROR: $e');
      }

      // Stage 2: If still not VIP, check whether the entered password IS a valid
      // VIP code. Use a single-field query + Dart-side status filter to avoid
      // requiring a composite Firestore index.
      if (!subService.isVip) {
        try {
          final enteredCode = _passwordController.text.trim().toUpperCase();
          if (enteredCode.isNotEmpty) {
            final vipQuery = await FirebaseFirestore.instance
                .collection('vip_codes')
                .where('code', isEqualTo: enteredCode)
                .limit(5)
                .get();
            final activeDoc = vipQuery.docs
                .where((d) => d.data()['status'] == 'active')
                .firstOrNull;
            if (activeDoc != null) {
              isSuperAdmin = activeDoc.data()['type'] == 'super_admin';
              await subService.setVipStatus(true);
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({'isVip': true, 'isSuperAdmin': isSuperAdmin}, SetOptions(merge: true));
              debugPrint('HARMONY_LOGIN_VIP: code match, isSuperAdmin=$isSuperAdmin');
            } else {
              debugPrint('HARMONY_LOGIN_VIP: no active code match for "$enteredCode" (docs=${vipQuery.docs.length})');
            }
          }
        } catch (e) {
          debugPrint('HARMONY_LOGIN_VIPCODE_ERROR: $e');
        }
      }

      // Stage 3: VIP codes assigned to this email address (single-field query).
      if (!subService.isVip && user.email != null && user.email!.isNotEmpty) {
        try {
          final emailsToTry = <String>{
            user.email!,
            user.email!.toLowerCase(),
            user.email!.toUpperCase(),
          };
          for (final email in emailsToTry) {
            final assignedVip = await FirebaseFirestore.instance
                .collection('vip_codes')
                .where('assignee', isEqualTo: email)
                .limit(10)
                .get();
            final activeDocs = assignedVip.docs
                .where((d) => d.data()['status'] == 'active')
                .toList();
            if (activeDocs.isNotEmpty) {
              isSuperAdmin = activeDocs.any((d) => d.data()['type'] == 'super_admin');
              await subService.setVipStatus(true);
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({'isVip': true, 'isSuperAdmin': isSuperAdmin}, SetOptions(merge: true));
              debugPrint('HARMONY_LOGIN_VIP: email assignee match ($email), isSuperAdmin=$isSuperAdmin');
              break;
            }
          }
        } catch (e) {
          debugPrint('HARMONY_LOGIN_EMAIL_ASSIGNEE_ERROR: $e');
        }
      }

      await subService.refreshSubscriptionStatus();

      if (!mounted) return;

      debugPrint('HARMONY_LOGIN_FINAL: isVip=${subService.isVip} isSubscribed=${subService.isSubscribed} isSuperAdmin=$isSuperAdmin');

      final Widget destination = subService.isSubscribed
          ? HomeScreen(isSuperAdmin: isSuperAdmin)
          : const SubscriptionScreen();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => destination),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String message;
        switch (e.code) {
          case 'user-not-found':
          case 'wrong-password':
          case 'invalid-credential':
            message = 'Incorrect email or password. Please try again.';
            break;
          case 'user-disabled':
            message = 'This account has been disabled. Please contact support.';
            break;
          case 'too-many-requests':
            message = 'Too many attempts. Please try again later.';
            break;
          default:
            message = 'Sign in failed: ${e.message}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An unexpected error occurred. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address above first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email. Please check your inbox.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.code == 'user-not-found'
                ? 'No account found with that email address.'
                : 'Could not send reset email: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Log In'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Welcome Back',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to continue your journey',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Email
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration('Email Address', Icons.email_outlined),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: _obscurePassword,
                  decoration: _inputDecoration('Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty) ? 'Please enter your password' : null,
                ),
                const SizedBox(height: 8),

                // Forgot Password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _handleForgotPassword,
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Log In button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.indigo.shade900,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Log In',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white30),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.redAccent),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.redAccent),
        borderRadius: BorderRadius.circular(12),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent),
      prefixIcon: Icon(icon, color: Colors.white70),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
