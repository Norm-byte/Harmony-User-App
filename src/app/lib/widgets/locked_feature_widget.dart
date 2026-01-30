import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';

class LockedFeatureWidget extends StatelessWidget {
  final Widget child;
  final String featureName;

  const LockedFeatureWidget({
    super.key,
    required this.child,
    required this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionService>(
      builder: (context, subService, _) {
        if (subService.isSubscribed) {
          return child;
        }

        return Stack(
          children: [
            // Blurred background content (optional, or just a placeholder)
            Opacity(
              opacity: 0.1,
              child: IgnorePointer(child: child),
            ),
            
            // Lock Overlay
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.amber.shade300, width: 2),
                      ),
                      child: Icon(Icons.lock_outline, size: 48, color: Colors.amber.shade300),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '$featureName is Locked',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Subscribe to unlock Chat Rooms, Topic Discussions, and Favorites. Join the conversation!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                           await subService.showPaywall();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Unable to load store: $e")),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      ),
                      icon: const Icon(Icons.star),
                      label: const Text('Unlock Full Access'),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        // Logic to restore purchases
                        subService.restorePurchases().then((value) {
                          if (value) {
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(content: Text("Subscription restored!"), backgroundColor: Colors.green),
                             );
                          } else {
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(content: Text("No active subscription found to restore.")),
                             );
                          }
                        });
                      },
                      child: const Text('Restore Purchases', style: TextStyle(color: Colors.white60)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
