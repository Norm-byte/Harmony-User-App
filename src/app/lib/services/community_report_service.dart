import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CommunityReportService {
  CommunityReportService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) : _functions = functions ?? FirebaseFunctions.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<CommunityPostReportResult> reportPost({
    required String postId,
    required String reason,
    String explanation = '',
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('Sign in before reporting a community post.');
    }
    final callable = _functions.httpsCallable('reportCommunityPost');
    final result = await callable.call<Map<String, dynamic>>({
      'postId': postId,
      'reason': reason,
      'explanation': explanation,
    });
    final data = result.data;
    return CommunityPostReportResult(
      accepted: data['accepted'] == true,
      duplicate: data['duplicate'] == true,
      autoHidden: data['autoHidden'] == true,
      distinctReportCount: (data['distinctReportCount'] as num?)?.toInt() ?? 0,
      threshold: (data['threshold'] as num?)?.toInt() ?? 3,
    );
  }
}

class CommunityPostReportResult {
  const CommunityPostReportResult({
    required this.accepted,
    required this.duplicate,
    required this.autoHidden,
    required this.distinctReportCount,
    required this.threshold,
  });

  final bool accepted;
  final bool duplicate;
  final bool autoHidden;
  final int distinctReportCount;
  final int threshold;
}
