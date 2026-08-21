import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
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
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _referralCodeController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  static const String _usernameTakenCode = 'username-taken';

  String? _assignedSellerCode() {
    final code = _referralCodeController.text.trim();
    return code.isEmpty ? null : code;
  }

  Future<void> _applySellerReferral({
    required String uid,
    required String sellerCode,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'assignedSellerCode': sellerCode,
    }, SetOptions(merge: true));

    await FirebaseAnalytics.instance.logEvent(
      name: 'seller_signup',
      parameters: {'seller_id': sellerCode},
    );

    await context.read<SubscriptionService>().setSubscriberAttributes({
        'assignedSellerCode': sellerCode,
      });
  }

  Future<void> _applySellerReferralIfPresent(String uid) async {
    final sellerCode = _assignedSellerCode();
    if (sellerCode == null) return;

    try {
      await _applySellerReferral(uid: uid, sellerCode: sellerCode);
    } catch (e) {
      debugPrint('HARMONY_SELLER_REFERRAL_ERROR: $e');
    }
  }

  Future<bool> _isUsernameAvailable(String username, {String? excludeUid}) async {
    final users = FirebaseFirestore.instance.collection('users');
    final lower = username.trim().toLowerCase();

    final normalizedSnapshot = await users
        .where('usernameLower', isEqualTo: lower)
        .limit(10)
        .get();
    for (final doc in normalizedSnapshot.docs) {
      if (excludeUid == null || doc.id != excludeUid) {
        return false;
      }
    }

    // Legacy fallback for older docs that may not have usernameLower.
    final legacyFields = ['username', 'userName', 'displayName', 'name'];
    for (final field in legacyFields) {
      final legacySnapshot = await users.where(field, isEqualTo: username).limit(10).get();
      for (final doc in legacySnapshot.docs) {
        if (excludeUid == null || doc.id != excludeUid) {
          return false;
        }
      }
    }

    return true;
  }

  Future<List<String>> _generateUsernameSuggestions(String requested) async {
    final suggestions = <String>[];
    final base = requested.replaceAll(' ', '').trim();
    final seed = DateTime.now().millisecondsSinceEpoch % 9000;

    var attempt = 0;
    while (suggestions.length < 3 && attempt < 60) {
      final suffix = (seed + (attempt * 17) + 100).toString();
      final rawCandidate = attempt.isEven ? '${base}_$suffix' : '$base$suffix';
      final candidate = UserService.sanitizePublicDisplayName(rawCandidate);

      if (candidate.toLowerCase() != requested.toLowerCase() &&
          UserService.isRecognizedPublicDisplayName(candidate) &&
          !suggestions.contains(candidate)) {
        final available = await _isUsernameAvailable(candidate);
        if (available) {
          suggestions.add(candidate);
        }
      }
      attempt++;
    }

    return suggestions;
  }

  Future<void> _reserveUsernameOrThrow({
    required String uid,
    required String username,
  }) async {
    final users = FirebaseFirestore.instance.collection('usernames');
    final normalized = username.trim().toLowerCase();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final ref = users.doc(normalized);
      final snapshot = await tx.get(ref);

      if (snapshot.exists) {
        final ownerUid = (snapshot.data()?['ownerUid'] as String?) ?? '';
        if (ownerUid.isNotEmpty && ownerUid != uid) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: _usernameTakenCode,
            message: 'Username is already claimed.',
          );
        }
      }

      tx.set(ref, {
        'username': username,
        'usernameLower': normalized,
        'ownerUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': snapshot.exists
            ? (snapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp())
            : FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<String?> _resolveAndReserveUsername(String uid) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final candidate = await _ensureAvailableUsername(excludeUid: uid);
      if (candidate == null) return null;

      try {
        await _reserveUsernameOrThrow(uid: uid, username: candidate);
        return candidate;
      } on FirebaseException catch (e) {
        if (e.code == _usernameTakenCode) {
          _showError('That username was just claimed by someone else. Please choose another one.');
          continue;
        }
        rethrow;
      }
    }

    _showError('Could not reserve a username right now. Please try again.');
    return null;
  }

  Future<String?> _promptUsernameSuggestion(
    String requested,
    List<String> suggestions,
  ) async {
    if (!mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Username already in use'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"$requested" is already taken.'),
              const SizedBox(height: 8),
              const Text('Try one of these:'),
              const SizedBox(height: 8),
              ...suggestions.map(
                (name) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(name),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.pop(ctx, name),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _ensureAvailableUsername({String? excludeUid}) async {
    final raw = _usernameController.text.trim();
    if (raw.isEmpty) {
      _showError('Please enter a username.');
      return null;
    }

    final sanitized = UserService.sanitizePublicDisplayName(raw);
    if (!UserService.isRecognizedPublicDisplayName(sanitized)) {
      _showError('Please choose a valid username.');
      return null;
    }

    final isAvailable = await _isUsernameAvailable(sanitized, excludeUid: excludeUid);
    if (isAvailable) {
      return sanitized;
    }

    final suggestions = await _generateUsernameSuggestions(sanitized);
    if (suggestions.isEmpty) {
      _showError('That username is already in use. Please choose another one.');
      return null;
    }

    final picked = await _promptUsernameSuggestion(sanitized, suggestions);
    if (picked == null) {
      return null;
    }

    _usernameController.text = picked;
    return picked;
  }

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
          final type = (vipData['type'] ?? 'beta_tester').toString();
          final isSuperAdmin = type == 'super_admin';
          final vipQuotaTier =
              (vipData['vipQuotaTier'] as String?)?.trim().isNotEmpty == true
                  ? (vipData['vipQuotaTier'] as String).trim()
                  : 'tier_beta';
          final fullName = _fullNameController.text.trim();
          final requestedUsername = await _ensureAvailableUsername();
          if (requestedUsername == null) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
            return;
          }
          var username = requestedUsername;
          final email = _emailController.text.trim();

          if (email.isEmpty) {
            if (mounted) {
              setState(() => _isLoading = false);
              _showError('Access code sign-up requires your email so your account can be recovered on login.');
            }
            return;
          }

          // Create (or sign in to) a real Firebase Auth account so the user
          // can log back in later with email + VIP code as their password.
          late final String uid;
          try {
            final cred = await FirebaseAuth.instance
                .createUserWithEmailAndPassword(email: email, password: potentialCode);
            await cred.user?.updateDisplayName(username);
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
                  _showError('This email already has an account with a different password. Use Log In, then your access code can be attached to that account.');
                }
                return;
              }
            } else {
              if (mounted) {
                setState(() => _isLoading = false);
                _showError('Access code sign up failed: ${e.message}');
              }
              return;
            }
          }

          final confirmedUsername = await _resolveAndReserveUsername(uid);
          if (confirmedUsername == null) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
            return;
          }
          username = confirmedUsername;
          await FirebaseAuth.instance.currentUser?.updateDisplayName(username);

          await UserService().setUser(uid, username);

          // Persist isVip in Firestore under the real Firebase Auth UID so the
          // login path can detect VIP status on future sign-ins.
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set({
                'createdAt': FieldValue.serverTimestamp(),
                'joinDate': FieldValue.serverTimestamp(),
                'isVip': true,
                'isSuperAdmin': isSuperAdmin,
                'vipQuotaTier': vipQuotaTier,
                'email': email,
                'fullName': fullName,
                'username': username,
                'usernameLower': username.toLowerCase(),
                'userName': username,
                'displayName': username,
                'name': username,
              }, SetOptions(merge: true));

          await _applySellerReferralIfPresent(uid);

          if (!mounted) return;
          Provider.of<SubscriptionService>(context, listen: false).setVipStatus(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isSuperAdmin ? 'Welcome Super Admin!' : 'Access Code Accepted — Full Access Unlocked!'),
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

    final fullName = _fullNameController.text.trim();
    final username = await _ensureAvailableUsername();
    if (username == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final credential = await _createFirebaseAccount(
      email,
      password,
      fullName,
    );
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
    String fullName,
  ) async {
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final uid = credential.user!.uid;
      final reservedUsername = await _resolveAndReserveUsername(uid);
      if (reservedUsername == null) {
        await credential.user?.delete();
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return null;
      }

      final username = reservedUsername;

      await credential.user?.updateDisplayName(username);
      await UserService().setUser(uid, username);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'createdAt': FieldValue.serverTimestamp(),
            'joinDate': FieldValue.serverTimestamp(),
            'email': email,
            'fullName': fullName,
            'username': username,
            'usernameLower': username.toLowerCase(),
            'userName': username,
            'displayName': username,
            'name': username,
          }, SetOptions(merge: true));

      await _applySellerReferralIfPresent(uid);
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
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (e.code == _usernameTakenCode) {
          _showError('That username is already in use. Please choose another one.');
        } else {
          _showError('Sign up failed: ${e.message ?? 'Unable to reserve username.'}');
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
                  controller: _fullNameController,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDecoration('Full Name', Icons.person_outline),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Please enter your full name' : null,
                ),
                const SizedBox(height: 16),

                // Username
                TextFormField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.none,
                  decoration: _inputDecoration('Username', Icons.alternate_email),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a username';
                    }
                    final sanitized = UserService.sanitizePublicDisplayName(
                      value,
                    );
                    if (!UserService.isRecognizedPublicDisplayName(sanitized)) {
                      return 'Please choose a valid username';
                    }
                    return null;
                  },
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

                // Promo / Referral Code
                TextFormField(
                  controller: _referralCodeController,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.characters,
                  decoration: _inputDecoration('Promo / Referral Code', Icons.sell_outlined),
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
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }
}
