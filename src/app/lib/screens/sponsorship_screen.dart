import 'package:flutter/material.dart';
import '../widgets/gradient_scaffold.dart';

class SponsorshipScreen extends StatefulWidget {
  const SponsorshipScreen({super.key});

  @override
  State<SponsorshipScreen> createState() => _SponsorshipScreenState();
}

class _SponsorshipScreenState extends State<SponsorshipScreen> {
  final _formKey = GlobalKey<FormState>();
  final _intentController = TextEditingController();
  final _dedicationController = TextEditingController();
  String _selectedTimeSlot = '15'; // '15' or '45'

  @override
  void dispose() {
    _intentController.dispose();
    _dedicationController.dispose();
    super.dispose();
  }

  void _submitSponsorship() {
    if (_formKey.currentState!.validate()) {
      // Mock submission
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sponsorship request submitted for approval!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Sponsor a Chime'),
        // backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dedicate a Chime Slot',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Propose content or a dedication for a specific chime slot. All submissions are subject to admin approval.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),

              // Time Slot Selection
              const Text('Preferred Time Slot', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedTimeSlot,
                dropdownColor: Colors.indigo.shade900,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.access_time, color: Colors.white70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                ),
                items: const [
                  DropdownMenuItem(value: '15', child: Text('Quarter Past (:15)')),
                  DropdownMenuItem(value: '45', child: Text('Quarter To (:45)')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedTimeSlot = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Intent / Content
              TextFormField(
                controller: _intentController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Proposed Intent / Content',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your proposed content';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Dedication
              TextFormField(
                controller: _dedicationController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Dedication (Optional)',
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: 'e.g., In memory of...',
                  hintStyle: TextStyle(color: Colors.white30),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                ),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitSponsorship,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Submit for Approval',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
