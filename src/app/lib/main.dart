import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';
import 'screens/event_overlay_screen.dart';
import 'services/event_service.dart';
import 'services/favorites_service.dart';
import 'services/user_service.dart';
import 'services/subscription_service.dart';
import 'services/notification_service.dart';
import 'services/group_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("HARMONY_APP_STARTING: This is the correct app!");

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("HARMONY_APP_FIREBASE: Initialized successfully");
    
    // Initialize Services
    await SubscriptionService().init();
    await NotificationService().init();
  } catch (e) {
    print("HARMONY_APP_FIREBASE_ERROR: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EventService()),
        ChangeNotifierProvider(create: (_) => FavoritesService()),
        ChangeNotifierProvider(create: (_) => UserService()),
        ChangeNotifierProvider(create: (_) => SubscriptionService()),
        ChangeNotifierProvider(create: (_) => GroupService(), lazy: false),
      ],
      child: const HarmonyUserApp(),
    ),
  );
}

class HarmonyUserApp extends StatelessWidget {
  const HarmonyUserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harmony User App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
          surface: Colors
              .transparent, // Important for cards to look good on gradient
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor:
            Colors.transparent, // Default to transparent for GradientScaffold
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      builder: (context, child) {
        return AppLifecycleManager(child: child!);
      },
      home: const SplashScreen(),
    );
  }
}

class AppLifecycleManager extends StatelessWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<EventService>(
      builder: (context, eventService, _) {
        return Stack(
          children: [
            child,
            if (eventService.isEventActive)
              Positioned.fill(
                child: EventOverlayScreen(
                  title: eventService.currentEventTitle,
                  description: eventService.currentEventDescription,
                  isWorldwide: eventService.isWorldwide,
                  mediaUrl: eventService.currentEventMediaUrl, // Pass mediaUrl
                  userIntent: eventService.userIntent, // Pass userIntent
                  onDismiss: eventService.dismissEvent,
                ),
              ),
          ],
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToWelcome();
  }

  _navigateToWelcome() async {
    // Check for maintenance mode
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('global')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final isMaintenance = data['maintenanceMode'] ?? false;
        if (isMaintenance) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => MaintenanceScreen(
                  message:
                      data['maintenanceMessage'] ?? 'System under maintenance.',
                ),
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      print("Error checking maintenance mode: $e");
    }

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.spa, size: 80, color: Colors.indigo.shade300),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Colors.indigo),
            const SizedBox(height: 24),
            const Text("Loading Harmony...", style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class MaintenanceScreen extends StatelessWidget {
  final String message;

  const MaintenanceScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.build_circle, size: 80, color: Colors.orange.shade300),
              const SizedBox(height: 24),
              const Text(
                "Under Maintenance",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  // Restart app logic or just re-check
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SplashScreen(),
                    ),
                  );
                },
                child: const Text("Check Again"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
