import 'package:flutter/material.dart';
import '../utils/profanity_filter.dart';

class IntentSelectionDialog extends StatefulWidget {
  final Function(String) onIntentSelected;

  const IntentSelectionDialog({super.key, required this.onIntentSelected});

  @override
  State<IntentSelectionDialog> createState() => _IntentSelectionDialogState();
}

class _IntentSelectionDialogState extends State<IntentSelectionDialog> {
  final TextEditingController _customIntentController = TextEditingController();

  @override
  void dispose() {
    _customIntentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manifest Your Intent'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a positive intent to focus on during this event:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
             const Text(
              'This is a free action and does not deduct from your credits.',
              style: TextStyle(fontSize: 12, color: Colors.green, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _customIntentController,
              decoration: const InputDecoration(
                labelText: 'Type your intent (max 5 words)',
                border: OutlineInputBorder(),
                hintText: 'e.g., Inner Strength',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final intent = _customIntentController.text.trim();
            if (intent.isNotEmpty) {
              if (ProfanityFilter.hasProfanity(intent)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please keep the intent positive and clean.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final wordCount = intent.split(RegExp(r'\s+')).length;
              if (wordCount > 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please limit your intent to 5 words.')),
                );
                return;
              }
              widget.onIntentSelected(intent);
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please type an intent')),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
          child: const Text('Join Event'),
        ),
      ],
    );
  }
}
