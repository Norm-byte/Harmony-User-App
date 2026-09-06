import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

class PreparedImageData {
  final Uint8List bytes;
  final int width;
  final int height;

  const PreparedImageData({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

class UploadedMediaRef {
  final String storagePath;
  final String downloadUrl;
  final int bytes;
  final int width;
  final int height;

  const UploadedMediaRef({
    required this.storagePath,
    required this.downloadUrl,
    required this.bytes,
    required this.width,
    required this.height,
  });
}

class MediaVaultService {
  static const int _maxDimension = 720;
  static const int _maxTargetBytes = 200 * 1024;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String monthKey(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchVaultImages(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('vault_images')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<int> getVaultImageCount(String uid) async {
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('vault_images')
        .where('status', isEqualTo: 'active')
        .get();
    return snap.docs.length;
  }

  Future<int> getSharedRoomUploadsForMonth(String uid, DateTime now) async {
    final key = monthKey(now);
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('usage_media')
        .doc(key)
        .get();
    final data = snap.data();
    if (data == null) return 0;
    return (data['sharedRoomUploads'] as num?)?.toInt() ?? 0;
  }

  Future<void> incrementSharedRoomUploadsForMonth(
    String uid,
    DateTime now, {
    int count = 1,
  }) async {
    final key = monthKey(now);
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('usage_media')
        .doc(key)
        .set({
      'sharedRoomUploads': FieldValue.increment(count),
      'totalUploads': FieldValue.increment(count),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteRoomMedia(String storagePath) async {
    if (storagePath.isEmpty) return;
    try {
      await _storage.ref(storagePath).delete();
    } catch (_) {
      // Best effort cleanup after a post fails before creation.
    }
  }

  Future<void> incrementVaultUploadsForMonth(String uid, DateTime now) async {
    final key = monthKey(now);
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('usage_media')
        .doc(key)
        .set({
      'vaultUploads': FieldValue.increment(1),
      'totalUploads': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<PreparedImageData> prepareImage(XFile file) async {
    final sourceBytes = await file.readAsBytes().timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw TimeoutException('Reading image timed out'),
    );
    final originalDimensions = await _readDimensions(sourceBytes);

    Uint8List compressed = sourceBytes;
    if (!kIsWeb) {
      compressed = await _compressFromPath(
        file.path,
        sourceBytes,
        originalWidth: originalDimensions.$1,
        originalHeight: originalDimensions.$2,
      );
      compressed = await _ensureJpegBytes(compressed, sourceBytes);
    }

    final dimensions = await _readDimensions(compressed);
    return PreparedImageData(
      bytes: compressed,
      width: dimensions.$1,
      height: dimensions.$2,
    );
  }

  Future<UploadedMediaRef> uploadToVault({
    required String uid,
    required PreparedImageData prepared,
    required String source,
  }) async {
    final imageId = _nextId();
    final storagePath = 'user_vault_media/$uid/$imageId.jpg';
    final ref = _storage.ref(storagePath);

    await ref.putData(
      prepared.bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    ).timeout(const Duration(minutes: 2));
    final downloadUrl = await ref.getDownloadURL().timeout(
      const Duration(seconds: 30),
    );

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('vault_images')
        .doc(imageId)
        .set({
      'imageId': imageId,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'bytes': prepared.bytes.length,
      'width': prepared.width,
      'height': prepared.height,
      'source': source,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return UploadedMediaRef(
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      bytes: prepared.bytes.length,
      width: prepared.width,
      height: prepared.height,
    );
  }

  Future<UploadedMediaRef> uploadToRoom({
    required String roomId,
    required String uid,
    required PreparedImageData prepared,
  }) async {
    final imageId = _nextId();
    final storagePath = 'chat_room_media/$roomId/$uid/$imageId.jpg';
    final ref = _storage.ref(storagePath);

    await ref.putData(
      prepared.bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    ).timeout(const Duration(minutes: 2));
    final downloadUrl = await ref.getDownloadURL().timeout(
      const Duration(seconds: 30),
    );

    return UploadedMediaRef(
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      bytes: prepared.bytes.length,
      width: prepared.width,
      height: prepared.height,
    );
  }

  Future<void> deleteVaultImage({
    required String uid,
    required String imageId,
    required String storagePath,
  }) async {
    try {
      if (storagePath.isNotEmpty) {
        await _storage.ref(storagePath).delete();
      }
    } catch (_) {
      // Best effort: continue and mark doc deleted even if storage object is gone.
    }

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('vault_images')
        .doc(imageId)
        .set({
      'status': 'deleted',
      'downloadUrl': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _nextId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'img_${now}_$rand';
  }

  Future<Uint8List> _compressFromPath(
    String path,
    Uint8List fallback, {
    required int originalWidth,
    required int originalHeight,
  }) async {
    const qualities = <int>[75, 65, 55, 45];
    Uint8List best = fallback;
    final target = _scaledDimensions(originalWidth, originalHeight);

    for (final q in qualities) {
      Uint8List? candidate;
      try {
        candidate = await FlutterImageCompress.compressWithFile(
          path,
          quality: q,
          minWidth: target.$1,
          minHeight: target.$2,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
      } catch (_) {
        candidate = null;
      }
      if (candidate == null) continue;
      best = candidate;
      if (best.length <= _maxTargetBytes) {
        break;
      }
    }

    return best;
  }

  (int, int) _scaledDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      return (_maxDimension, _maxDimension);
    }

    final maxEdge = width > height ? width : height;
    if (maxEdge <= _maxDimension) {
      return (width, height);
    }

    final scale = _maxDimension / maxEdge;
    final scaledWidth = (width * scale).round().clamp(1, _maxDimension);
    final scaledHeight = (height * scale).round().clamp(1, _maxDimension);
    return (scaledWidth, scaledHeight);
  }

  Future<Uint8List> _ensureJpegBytes(Uint8List primary, Uint8List fallback) async {
    if (_looksLikeJpeg(primary)) {
      return primary;
    }

    try {
      final converted = await FlutterImageCompress.compressWithList(
        primary,
        quality: 72,
        minWidth: _maxDimension,
        minHeight: _maxDimension,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (converted.isNotEmpty && _looksLikeJpeg(converted)) {
        return converted;
      }
    } catch (_) {}

    try {
      final convertedFallback = await FlutterImageCompress.compressWithList(
        fallback,
        quality: 72,
        minWidth: _maxDimension,
        minHeight: _maxDimension,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (convertedFallback.isNotEmpty && _looksLikeJpeg(convertedFallback)) {
        return convertedFallback;
      }
    } catch (_) {}

    return primary;
  }

  bool _looksLikeJpeg(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0xFF && bytes[1] == 0xD8;
  }

  Future<(int, int)> _readDimensions(Uint8List data) async {
    try {
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      return (frame.image.width, frame.image.height);
    } catch (_) {
      return (0, 0);
    }
  }
}
