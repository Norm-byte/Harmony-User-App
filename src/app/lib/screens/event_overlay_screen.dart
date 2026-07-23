import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_service.dart';
import '../widgets/media/content_viewer.dart';

class EventOverlayScreen extends StatelessWidget {
  final String title;
  final String description;
  final bool isWorldwide;
  final String? mediaUrl;
  final String? userIntent;
  final String? eventId;
  final int participantCount;
  final String? originTimeZone;
  final VoidCallback onDismiss;

  const EventOverlayScreen({
    super.key,
    required this.title,
    required this.description,
    required this.isWorldwide,
    this.mediaUrl,
    this.userIntent,
    this.eventId,
    this.participantCount = 0,
    this.originTimeZone,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    isWorldwide
                        ? Colors.purple.shade900
                        : Colors.indigo.shade900,
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),
          if (mediaUrl != null && mediaUrl!.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: ContentViewer(
                  url: mediaUrl!,
                  fit: BoxFit.cover,
                  controls: false,
                  autoPlay: true,
                  loop: true,
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      isWorldwide
                          ? Colors.purple.shade900
                          : Colors.indigo.shade900,
                      Colors.black,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    isWorldwide ? Icons.public : Icons.music_note,
                    size: 120,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),

          Positioned.fill(
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 72, 24, 120),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: const [],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                      left: 12,
                      right: 12,
                      bottom: 20,
                      child: _OverlayLiveStatsLayer(
                        eventId: eventId,
                        participantCount: participantCount,
                        originTimeZone: originTimeZone,
                      ),
                    ),
                    Positioned(
                    right: 16,
                    bottom: 20,
                    child: TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Exit Event',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayLiveStatsLayer extends StatefulWidget {
  final String? eventId;
  final int participantCount;
  final String? originTimeZone;

  const _OverlayLiveStatsLayer({
    required this.eventId,
    required this.participantCount,
    required this.originTimeZone,
  });

  @override
  State<_OverlayLiveStatsLayer> createState() => _OverlayLiveStatsLayerState();
}

class _OverlayLiveStatsLayerState extends State<_OverlayLiveStatsLayer> {
  Timer? _timer;
  int _liveViewers = 0;
  List<String> _activeFlags = const [];
  List<String> _activeZones = const [];
  String? _presenceSessionId;
  String? _countryCode;
  String? _flagEmoji;
  String? _activePresenceEventId;

  @override
  void initState() {
    super.initState();
    _refreshLiveData();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshLiveData();
    });
  }

  @override
  void didUpdateWidget(covariant _OverlayLiveStatsLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) {
      unawaited(_stopPresenceSession(eventIdOverride: oldWidget.eventId));
      _refreshLiveData();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_stopPresenceSession());
    super.dispose();
  }

  Future<void> _refreshLiveData() async {
    final id = (widget.eventId ?? '').trim();
    if (id.isEmpty) {
      if (mounted) {
        setState(() {
          _liveViewers = 0;
          _activeFlags = const [];
          _activeZones = const [];
        });
      }
      return;
    }

    try {
      await _heartbeatPresence(id);

      final cutoff = DateTime.now().subtract(const Duration(seconds: 15));
      final active = await FirebaseFirestore.instance
          .collection('event_live_viewers')
          .doc(id)
          .collection('sessions')
          .where('lastSeenAt', isGreaterThan: Timestamp.fromDate(cutoff))
          .get();

      final Map<String, int> flagHits = {};
      final Map<String, int> zoneHits = {};

      for (final doc in active.docs) {
        final data = doc.data();
        final directFlag = (data['flagEmoji'] as String?)?.trim();
        String? flag =
            (directFlag != null && directFlag.isNotEmpty) ? directFlag : null;

        if (flag == null) {
          final code = (data['countryCode'] as String?)?.trim().toUpperCase();
          if (code != null && code.length == 2) {
            flag = _countryCodeToFlag(code);
          }
        }

        if (flag != null && flag.isNotEmpty) {
          flagHits[flag] = (flagHits[flag] ?? 0) + 1;
        } else {
          final zone = (data['timeZone'] as String?)?.trim();
          if (zone != null && zone.isNotEmpty) {
            zoneHits[zone] = (zoneHits[zone] ?? 0) + 1;
          }
        }
      }

      final sortedFlags = flagHits.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final nextFlags = sortedFlags.take(4).map((e) => e.key).toList();

      final sortedZones = zoneHits.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final nextZones = sortedZones.take(3).map((e) => e.key).toList();

      if (!mounted) return;
      setState(() {
        _liveViewers = active.docs.length;
        _activeFlags = nextFlags;
        _activeZones = nextZones;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liveViewers = 0;
        _activeFlags = const [];
        _activeZones = const [];
      });
    }
  }

  Future<void> _heartbeatPresence(String eventId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) return;

    final sessionId = await _resolvePresenceSessionId();
    if (sessionId.isEmpty) return;

    await _ensureGeoIdentity();

    final eventRef = FirebaseFirestore.instance
        .collection('event_live_viewers')
        .doc(eventId);

    await eventRef.set({
      'eventId': eventId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await eventRef.collection('sessions').doc(sessionId).set({
      'sessionId': sessionId,
      'userId': userId,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'timeZone': UserService().timeZone,
      'countryCode': _countryCode,
      'flagEmoji': _flagEmoji,
    }, SetOptions(merge: true));

    _activePresenceEventId = eventId;
  }

  Future<String> _resolvePresenceSessionId() async {
    final cached = _presenceSessionId?.trim();
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('presence_session_id')?.trim();
    if (existing != null && existing.isNotEmpty) {
      _presenceSessionId = existing;
      return existing;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 1000000;
    final generated =
        'session_${timestamp}_${random.toString().padLeft(6, '0')}';
    await prefs.setString('presence_session_id', generated);
    _presenceSessionId = generated;
    return generated;
  }

  Future<void> _ensureGeoIdentity() async {
    if ((_countryCode != null && _countryCode!.isNotEmpty) ||
        (_flagEmoji != null && _flagEmoji!.isNotEmpty)) {
      return;
    }

    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final profileUserId = UserService().userId.isNotEmpty
        ? UserService().userId
        : (authUid ?? '');
    if (profileUserId.isEmpty) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(profileUserId)
          .get();
      final data = userDoc.data();
      if (data == null) return;

      final codeCandidates = [
        data['countryCode'],
        data['country_code'],
        data['country'],
      ];

      for (final candidate in codeCandidates) {
        final value = (candidate as String?)?.trim().toUpperCase();
        if (value != null && value.length == 2) {
          _countryCode = value;
          break;
        }
      }

      final explicitFlag = (data['flagEmoji'] as String?)?.trim();
      if (explicitFlag != null && explicitFlag.isNotEmpty) {
        _flagEmoji = explicitFlag;
      } else if (_countryCode != null) {
        _flagEmoji = _countryCodeToFlag(_countryCode!);
      }
    } catch (_) {
      // Best-effort enrichment only.
    }
  }

  Future<void> _stopPresenceSession({String? eventIdOverride}) async {
    final sessionId = _presenceSessionId?.trim() ?? '';
    final eventId = (eventIdOverride ?? _activePresenceEventId ?? '').trim();
    if (sessionId.isEmpty || eventId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('event_live_viewers')
          .doc(eventId)
          .collection('sessions')
          .doc(sessionId)
          .delete();
    } catch (_) {
      // Cleanup is best-effort.
    }
  }

  String _countryCodeToFlag(String code) {
    if (code.length != 2) return '';
    final upper = code.toUpperCase();
    final first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final showLiveStats = data['showLiveStats'] == true;
        if (!showLiveStats) {
          return const SizedBox.shrink();
        }

        final position = (data['statsOverlayPosition'] as String? ?? 'bottom')
            .trim()
            .toLowerCase();
        final metric =
            (data['statsParticipantMetric'] as String? ?? 'all_viewers')
                .trim()
                .toLowerCase();
        final includeDormant = data['statsIncludeDormantOverrides'] == true;
        final showFlags = data['statsShowTimezoneFlags'] == true;

        int displayCount =
            metric == 'participants_only' ? widget.participantCount : _liveViewers;
        if (includeDormant && widget.participantCount > displayCount) {
          displayCount = widget.participantCount;
        }

        final alignment =
          position == 'right' ? Alignment.bottomRight : Alignment.bottomLeft;
        final label =
            metric == 'participants_only' ? 'participants' : 'live viewers';

        return Align(
          alignment: alignment,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.groups_2,
                    size: 14,
                    color: Colors.lightGreenAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$displayCount $label',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.originTimeZone != null &&
                      widget.originTimeZone!.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      widget.originTimeZone!.trim(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (showFlags && _activeFlags.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(_activeFlags.join(' '), style: const TextStyle(fontSize: 12)),
                  ] else if (showFlags && _activeZones.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      _activeZones.join(' · '),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
          ),
        );
      },
    );
  }
}
