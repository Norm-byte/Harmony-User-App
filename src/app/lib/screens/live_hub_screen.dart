import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LiveHubScreen extends StatefulWidget {
  const LiveHubScreen({super.key});

  @override
  State<LiveHubScreen> createState() => _LiveHubScreenState();
}

class _LiveHubScreenState extends State<LiveHubScreen> {
  String _selectedGenre = 'All';

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Live Hub'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('app_config').doc('live_hub').snapshots(),
        builder: (context, settingsSnapshot) {
          final settings = settingsSnapshot.data?.data() ?? const <String, dynamic>{};
          final configuredGenres = (settings['genres'] as List<dynamic>? ?? const [])
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList();
          final genres = ['All', ...configuredGenres];
          if (!genres.contains(_selectedGenre)) _selectedGenre = 'All';
          final backgroundUrl = (settings['backgroundImageUrl'] ?? '').toString().trim();
          return Stack(
            children: [
              if (backgroundUrl.isNotEmpty)
                Positioned.fill(
                  child: Image.network(
                    backgroundUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.55))),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('live_events')
            .where('isPublished', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Live shows are temporarily unavailable.', style: TextStyle(color: Colors.white70)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }

          final now = DateTime.now();
          final events = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            final start = _asDate(data['startTime']);
            final duration = (data['durationMinutes'] as num?)?.toInt() ?? 60;
            final genre = (data['genre'] ?? '').toString();
            final isCurrentOrUpcoming = start != null && now.isBefore(start.add(Duration(minutes: duration)));
            return isCurrentOrUpcoming && (_selectedGenre == 'All' || genre == _selectedGenre);
          }).toList()
            ..sort((a, b) {
              final first = _asDate(a.data()['startTime']) ?? DateTime(2100);
              final second = _asDate(b.data()['startTime']) ?? DateTime(2100);
              return first.compareTo(second);
            });

          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: genres.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final genre = genres[index];
                    return ChoiceChip(
                      label: Text(genre),
                      selected: _selectedGenre == genre,
                      selectedColor: Colors.amber,
                      labelStyle: TextStyle(color: _selectedGenre == genre ? Colors.black : Colors.white),
                      backgroundColor: Colors.white12,
                      onSelected: (_) => setState(() => _selectedGenre = genre),
                    );
                  },
                ),
              ),
              Expanded(
                child: events.isEmpty
                    ? const Center(
                        child: Text('No live shows are scheduled right now.', style: TextStyle(color: Colors.white70)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: events.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _LiveEventCard(
                          data: events[index].data(),
                          startTime: _asDate(events[index].data()['startTime'])!,
                        ),
                      ),
              ),
            ],
          );
              },
            ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveEventCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final DateTime startTime;

  const _LiveEventCard({required this.data, required this.startTime});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final duration = (data['durationMinutes'] as num?)?.toInt() ?? 60;
    final isLive = !now.isBefore(startTime) && now.isBefore(startTime.add(Duration(minutes: duration)));
    final title = (data['title'] ?? 'Live show').toString();
    final host = (data['hostName'] ?? 'Harmony host').toString();
    final genre = (data['genre'] ?? 'Live').toString();
    final posterUrl = (data['posterImageUrl'] ?? '').toString();

    return Card(
      color: Colors.white12,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (posterUrl.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(posterUrl, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    if (isLive)
                      const Chip(label: Text('LIVE NOW'), backgroundColor: Colors.redAccent),
                    Text(
                      genre,
                      style: const TextStyle(color: Colors.white60),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(host, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Text(
                  isLive ? 'Now live' : 'Starts ${MaterialLocalizations.of(context).formatFullDate(startTime)} at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(startTime))}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}