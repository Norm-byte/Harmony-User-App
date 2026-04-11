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

          await UserService().setUser(potentialCode, fullName.isNotEmpty ? fullName : 'VIP Member');

          if (mounted) {
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
          }
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


class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleSignUp() async {
    final inputUsername = _usernameController.text.trim();
    // Codes are stored as Uppercase only in Admin/DB. Convert input to check.
    final potentialCode = inputUsername.toUpperCase();
    
    setState(() => _isLoading = true);

    // 1. Check for ANY VIP Code (Super Admin OR Beta Tester)
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
        
        // Both types bypass subscription now (Privileged Access)
        // BUG FIX: Don't use code as username.
        if (mounted) {
           // Use Full Name as the display username if they used a VIP Code
           // This protects the code from being displayed in Chat
           final fullName = _nameController.text.trim();
           
           _completeSignUp(
             isSuperAdmin: type == 'super_admin',
             username: potentialCode, // ID remains the code (for login)
             displayName: fullName.isNotEmpty ? fullName : "VIP Member", // Display Name
             bypassSubscription: true
           );
        }
        return;
      } else {
        // Not found as a VIP code, continue to standard sign up
        print('Code "$potentialCode" not found, checking if valid as standard username.');
      }
    } catch (e) {
      print('Error checking vip code: $e');
    }

    // Standard validation
    if (!_formKey.currentState!.validate()) {
      setState(() => _isLoading = false);
      return;
    }

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Complete Sign Up -> Go to Subscription
    if (mounted) {
      _completeSignUp(
        isSuperAdmin: false, 
        username: inputUsername, 
        displayName: inputUsername, // Standard user: Username is Display Name
        bypassSubscription: false
      );
    }
  }

  void _completeSignUp({
    required bool isSuperAdmin, 
    required String username, 
    required String displayName,
    required bool bypassSubscription
  }) {
    // Set ID (username variable) and Display Name separately
    UserService().setUser(username, displayName);

    if (bypassSubscription) {
      // CRITICAL: Tell SubscriptionService we are VIP!
      Provider.of<SubscriptionService>(context, listen: false).setVipStatus(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isSuperAdmin ? 'Welcome Super Admin!' : 'VIP Code Accepted - Subscription Unlocked!'), 
          backgroundColor: Colors.green
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(isSuperAdmin: isSuperAdmin)),
      );
    } else {
      // Regular user -> Go to Subscription Screen
      // Ensure VIP is OFF
      Provider.of<SubscriptionService>(context, listen: false).setVipStatus(false);
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
      );
    }
  }

  // _showPublicUsernameDialog removed (Logic simplified to use Full Name)

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
                
                // Name Field
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: const TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: const TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.white70),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Username Field (Dual purpose: Username or VIP Code)
                TextFormField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Username',
                    labelStyle: const TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.alternate_email, color: Colors.white70),
                    helperText: 'Choose a unique username',
                    helperStyle: const TextStyle(color: Colors.white54),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please choose a username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Submit Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignUp,
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
                      : const Text(
                          'Continue',
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

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}
