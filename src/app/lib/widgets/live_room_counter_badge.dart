import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/user_service.dart';

class LiveRoomCounterBadge extends StatefulWidget {
  final String roomId;
  final bool enabled;
  final bool showFlags;

  const LiveRoomCounterBadge({
    super.key,
    required this.roomId,
    required this.enabled,
    this.showFlags = false,
  });

  @override
  State<LiveRoomCounterBadge> createState() => _LiveRoomCounterBadgeState();
}

class _LiveRoomCounterBadgeState extends State<LiveRoomCounterBadge> {
  Timer? _heartbeatTimer;
  int _activeCount = 0;
  List<String> _activeFlags = const [];
  List<String> _activeZones = const [];
  String? _countryCode;
  String? _flagEmoji;
  String? _presenceSessionId;

  @override
  void initState() {
    super.initState();
    _syncPresenceLifecycle();
  }

  @override
  void didUpdateWidget(covariant LiveRoomCounterBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId || oldWidget.enabled != widget.enabled) {
      _syncPresenceLifecycle();
    }
  }

  @override
  void dispose() {
    unawaited(_stopPresenceSession());
    super.dispose();
  }

  Future<void> _syncPresenceLifecycle() async {
    await _stopPresenceSession(keepCount: true);
    if (!widget.enabled) {
      if (mounted) {
        setState(() => _activeCount = 0);
      }
      return;
    }

    await _heartbeatAndRefresh();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _heartbeatAndRefresh();
    });
  }

  Future<void> _heartbeatAndRefresh() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final sessionId = await _resolvePresenceSessionId();
    if (userId.isEmpty || sessionId.isEmpty || widget.roomId.trim().isEmpty) {
      return;
    }

    final profileUserId = UserService().userId.isNotEmpty
        ? UserService().userId
        : userId;
    await _ensureGeoIdentity(profileUserId);

    final roomRef = FirebaseFirestore.instance
        .collection('room_live_presence')
        .doc(widget.roomId);

    try {
      await roomRef.set({
        'roomId': widget.roomId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await roomRef.collection('sessions').doc(sessionId).set({
        'sessionId': sessionId,
        'userId': userId,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'timeZone': UserService().timeZone,
        'countryCode': _countryCode,
        'flagEmoji': _flagEmoji,
      }, SetOptions(merge: true));

      final cutoff = DateTime.now().subtract(const Duration(seconds: 15));
      final active = await roomRef
          .collection('sessions')
          .where('lastSeenAt', isGreaterThan: Timestamp.fromDate(cutoff))
          .get();

      print(
        'HARMONY_ROOM_DEBUG: room=${widget.roomId} uid=$userId '
        'session=$sessionId active=${active.docs.length}',
      );

      final Map<String, int> flagHits = {};
      final Map<String, int> zoneHits = {};
      for (final doc in active.docs) {
        final data = doc.data();
        final direct = (data['flagEmoji'] as String?)?.trim();
        String? flag = (direct != null && direct.isNotEmpty) ? direct : null;

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

      if (mounted) {
        setState(() {
          _activeCount = active.docs.length;
          _activeFlags = nextFlags;
          _activeZones = nextZones;
        });
      }
    } catch (_) {
      // Keep silent in production UI; this widget is best-effort.
    }
  }

  Future<void> _ensureGeoIdentity(String userId) async {
    if ((_countryCode != null && _countryCode!.isNotEmpty) ||
        (_flagEmoji != null && _flagEmoji!.isNotEmpty)) {
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
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
      // Best-effort enrichment.
    }
  }

  String _countryCodeToFlag(String code) {
    if (code.length != 2) return '';
    final upper = code.toUpperCase();
    final first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  Future<void> _stopPresenceSession({bool keepCount = false}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final sessionId = _presenceSessionId?.trim() ?? '';
    if (sessionId.isNotEmpty && widget.roomId.trim().isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('room_live_presence')
            .doc(widget.roomId)
            .collection('sessions')
            .doc(sessionId)
            .delete();
      } catch (_) {
        // Ignore cleanup failures.
      }
    }

    if (!keepCount && mounted) {
      setState(() => _activeCount = 0);
    }
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
    final generated = 'session_${timestamp}_${random.toString().padLeft(6, '0')}';
    await prefs.setString('presence_session_id', generated);
    _presenceSessionId = generated;
    return generated;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups_2, size: 13, color: Colors.lightGreenAccent),
          const SizedBox(width: 4),
          Text(
            '$_activeCount live',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (widget.showFlags && _activeFlags.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              _activeFlags.join(' '),
              style: const TextStyle(fontSize: 13),
            ),
          ] else if (widget.showFlags && _activeZones.isNotEmpty) ...[
            const SizedBox(width: 6),
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
    );
  }
}
