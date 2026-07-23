import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/event_overlay_screen.dart';
import 'services/event_service.dart';
import 'services/favorites_service.dart';
import 'services/user_service.dart';
import 'services/subscription_service.dart';
import 'services/notification_service.dart';
import 'services/group_service.dart';
import 'services/usage_service.dart';
import 'services/profanity_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("HARMONY_APP_STARTING: This is the correct app!");

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("HARMONY_APP_FIREBASE: Initialized successfully");

    // Initialize Services
    await SubscriptionService().init();
    await NotificationService().init();
    await ProfanityService().init();
  } catch (e) {
    debugPrint("HARMONY_APP_FIREBASE_ERROR: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EventService()),
        ChangeNotifierProvider(create: (_) => FavoritesService()),
        ChangeNotifierProvider(create: (_) => UserService()),
        ChangeNotifierProvider(create: (_) => SubscriptionService()),
        ChangeNotifierProxyProvider<SubscriptionService, UsageService>(
          create: (context) =>
              UsageService(context.read<SubscriptionService>()),
          update: (context, subscription, previous) =>
              UsageService(subscription),
        ),
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

class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App starts in foreground.
    context.read<EventService>().setAppInForegroundState(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    context.read<EventService>().setAppInForegroundState(isForeground);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EventService>(
      builder: (context, eventService, _) {
        return Stack(
          children: [
            widget.child,
            if (eventService.isAlarmLaunchTransitionActive &&
                !eventService.isEventActive)
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
            if (eventService.isEventActive)
              Positioned.fill(
                child: EventOverlayScreen(
                  title: eventService.currentEventTitle,
                  description: eventService.currentEventDescription,
                  isWorldwide: eventService.isWorldwide,
                  mediaUrl: eventService.currentEventMediaUrl, // Pass mediaUrl
                  userIntent: eventService.userIntent,
                  eventId: eventService.currentEventId,
                  participantCount: eventService.currentEventParticipantCount,
                  originTimeZone: eventService.currentEventOriginTimeZone,
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
  bool _launchCheckResolved = false;
  bool _suppressSplashVisuals = false;
  bool _navigationCompleted = false;

  @override
  void initState() {
    super.initState();
    // Watchdog: force navigation after 8 seconds if it hangs (iOS fix)
    Future.delayed(const Duration(seconds: 8), () {
      if (!mounted || _navigationCompleted) return;
      debugPrint(
        'HARMONY_STARTUP: splash watchdog fired, forcing Welcome navigation',
      );
      _navigationCompleted = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
      );
    });
    _navigateToWelcome();
  }

  _navigateToWelcome() async {
    String? launchEventId;
    bool autoPlayVideo = false;
    bool launchedFromAlarm = false;
    try {
      final payload = await NotificationService()
          .consumeLaunchPayload()
          .timeout(const Duration(seconds: 1), onTimeout: () => {});
      final eventIdRaw = payload['event_id'];
      if (eventIdRaw is String && eventIdRaw.isNotEmpty) {
        launchEventId = eventIdRaw;
      }
      autoPlayVideo = payload['auto_play_video'] == true;

      if (launchEventId == null || launchEventId.isEmpty) {
        launchEventId = await NotificationService()
            .consumeLaunchEventId()
            .timeout(const Duration(seconds: 1), onTimeout: () => null);
      }

      if (launchEventId != null && launchEventId.isNotEmpty) {
        launchedFromAlarm = true;
        context.read<EventService>().requestImmediateAlarmPlayback(
          launchEventId,
          forceVideo: autoPlayVideo,
        );
        debugPrint(
          'HARMONY_ALARM: launch event received in splash: $launchEventId',
        );
      }

      if (mounted) {
        setState(() {
          _launchCheckResolved = true;
          // Keep splash visible even for alarm launches to avoid a permanent
          // blank screen when alarm payload handoff stalls on iOS.
          _suppressSplashVisuals = false;
        });
      }
    } catch (e) {
      debugPrint('HARMONY_ALARM: failed to read launch event: $e');
      if (mounted) {
        setState(() {
          _launchCheckResolved = true;
          _suppressSplashVisuals = false;
        });
      }
    }

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
            _navigationCompleted = true;
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
      debugPrint("Error checking maintenance mode: $e");
    }

    await Future.delayed(
      launchEventId == null
          ? const Duration(seconds: 2)
          : const Duration(milliseconds: 300),
    );

    if (launchedFromAlarm) {
      debugPrint('HARMONY_ALARM: skipping Welcome navigation for alarm launch');
      return;
    }

    if (mounted) {
      final firebaseUser = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => FirebaseAuth.instance.currentUser,
          );
      if (firebaseUser != null) {
        // Already authenticated: require VIP or active subscription before Home.
        final subscriptionService = context.read<SubscriptionService>();
        await subscriptionService.refreshVipFromAuthUser();
        await subscriptionService.refreshSubscriptionStatus();

        if (!mounted) return;

        if (subscriptionService.isSubscribed) {
          _navigationCompleted = true;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  HomeScreen(isSuperAdmin: subscriptionService.isVip),
            ),
          );
        } else {
          _navigationCompleted = true;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
          );
        }
      } else {
        _navigationCompleted = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_launchCheckResolved || _suppressSplashVisuals) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
