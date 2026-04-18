import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../widgets/gradient_scaffold.dart';
import '../services/user_service.dart';
import '../services/subscription_service.dart';
import 'home_screen.dart';
import 'subscription_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  Future<void> _handleSignUp() async {
    // Check VIP code FIRST — before any form validation.
    // VIP users enter their code in the password field; no one else can see it.
    final potentialCode = _passwordController.text.trim().toUpperCase();
    if (potentialCode.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final vipQuery = await FirebaseFirestore.instance
            .collection('vip_codes')
            .where('code', isEqualTo: potentialCode)
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get();

        if (vipQuery.docs.isNotEmpty) {
          final vipData = vipQuery.docs.first.data();
          final type = vipData['type'] ?? 'beta_tester';
          final isSuperAdmin = type == 'super_admin';
          final fullName = _nameController.text.trim();
          final email = _emailController.text.trim();

          if (email.isEmpty) {
            if (mounted) {
              setState(() => _isLoading = false);
              _showError('VIP access requires your email so your account can be recovered on login.');
            }
            return;
          }

          // Create (or sign in to) a real Firebase Auth account so the user
          // can log back in later with email + VIP code as their password.
          late final String uid;
          try {
            final cred = await FirebaseAuth.instance
                .createUserWithEmailAndPassword(email: email, password: potentialCode);
            await cred.user?.updateDisplayName(fullName.isNotEmpty ? fullName : 'VIP Member');
            uid = cred.user!.uid;
          } on FirebaseAuthException catch (e) {
            if (e.code == 'email-already-in-use') {
              try {
                final cred = await FirebaseAuth.instance
                    .signInWithEmailAndPassword(email: email, password: potentialCode);
                uid = cred.user!.uid;
              } on FirebaseAuthException {
                if (mounted) {
                  setState(() => _isLoading = false);
                  _showError('This email already has an account with a different password. Use Log In, then your VIP access will be attached to that account.');
                }
                return;
              }
            } else {
              if (mounted) {
                setState(() => _isLoading = false);
                _showError('VIP sign up failed: ${e.message}');
              }
              return;
            }
          }

          await UserService().setUser(uid, fullName.isNotEmpty ? fullName : 'VIP Member');

          // Persist isVip in Firestore under the real Firebase Auth UID so the
          // login path can detect VIP status on future sign-ins.
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set({
                'isVip': true,
                'isSuperAdmin': isSuperAdmin,
                'email': email,
              }, SetOptions(merge: true));

          if (!mounted) return;
          Provider.of<SubscriptionService>(context, listen: false).setVipStatus(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isSuperAdmin ? 'Welcome Super Admin!' : 'VIP Code Accepted — Full Access Unlocked!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen(isSuperAdmin: isSuperAdmin)),
          );
          return;
        }
      } catch (e) {
        // Not a network/Firestore error worth surfacing — just not a VIP code.
      }
    }

    // Standard sign-up — run full form validation now
    if (!_formKey.currentState!.validate()) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    final fullName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final credential = await _createFirebaseAccount(email, password, fullName);
    if (credential == null) return;

    if (mounted) {
      Provider.of<SubscriptionService>(context, listen: false).setVipStatus(false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
      );
    }
  }

  /// Creates a Firebase Auth account and updates UserService. Returns the
  /// UserCredential on success, or null if an error occurred (error already shown).
  Future<UserCredential?> _createFirebaseAccount(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      await credential.user?.updateDisplayName(displayName);
      await UserService().setUser(credential.user!.uid, displayName);
      return credential;
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        switch (e.code) {
          case 'email-already-in-use':
            _showError('An account with this email already exists. Please log in instead.');
            break;
          case 'invalid-email':
            _showError('Please enter a valid email address.');
            break;
          case 'weak-password':
            _showError('Password is too weak. Please use at least 6 characters.');
            break;
          default:
            _showError('Sign up failed: ${e.message}');
        }
      }
      return null;
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('An unexpected error occurred. Please try again.');
      }
      return null;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
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
                  'Join the Community',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Full Name
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDecoration('Full Name', Icons.person_outline),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 16),

                // Email
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration('Email Address', Icons.email_outlined),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your email';
                    if (!value.contains('@') || !value.contains('.')) return 'Please enter a valid email';
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
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter a password';
                    if (value.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password
                TextFormField(
                  controller: _confirmPasswordController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: _obscureConfirm,
                  decoration: _inputDecoration('Confirm Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please confirm your password';
                    if (value != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Submit
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignUp,
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
                          'Create Account',
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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
