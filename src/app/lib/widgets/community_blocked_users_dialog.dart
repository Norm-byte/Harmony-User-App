import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/user_service.dart';

Future<void> showCommunityBlockedUsersDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _BlockedUsersDialog(),
  );
}

class _BlockedUsersDialog extends StatefulWidget {
  const _BlockedUsersDialog();

  @override
  State<_BlockedUsersDialog> createState() => _BlockedUsersDialogState();
}

class _BlockedUsersDialogState extends State<_BlockedUsersDialog> {
  late final Future<Map<String, String>> _names = _loadNames();
  final Set<String> _unblocking = {};

  Future<Map<String, String>> _loadNames() async {
    final entries = await Future.wait(
      UserService().blockedUsers.map((id) async {
        var name = 'Member (name unavailable)';
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(id)
              .get()
              .timeout(const Duration(seconds: 10));
          final data = snapshot.data();
          for (final key in ['username', 'userName', 'name', 'displayName']) {
            final candidate = UserService.sanitizePublicDisplayName(
              data?[key]?.toString(),
            );
            if (UserService.isRecognizedPublicDisplayName(candidate)) {
              name = candidate;
              break;
            }
          }
        } catch (_) {
          // A missing profile must not prevent unblocking the account.
        }
        return MapEntry(id, name);
      }),
    );
    return Map.fromEntries(entries);
  }

  Future<void> _unblock(String id) async {
    setState(() => _unblocking.add(id));
    try {
      await UserService().unblockUser(id);
    } finally {
      if (mounted) setState(() => _unblocking.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _names,
      builder: (context, snapshot) {
        final names = snapshot.data ?? const <String, String>{};
        final blockedUsers = List<String>.from(UserService().blockedUsers)
          ..sort((a, b) {
            final comparison = (names[a] ?? '').toLowerCase().compareTo(
              (names[b] ?? '').toLowerCase(),
            );
            return comparison == 0 ? a.compareTo(b) : comparison;
          });
        return AlertDialog(
          title: const Text('Blocked users'),
          content: SizedBox(
            width: 420,
            height: blockedUsers.isEmpty ? null : MediaQuery.sizeOf(context).height * 0.45,
            child: blockedUsers.isEmpty
                ? const Text('You have not blocked anyone.')
                : snapshot.connectionState != ConnectionState.done
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                    itemCount: blockedUsers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final userId = blockedUsers[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          names[userId] ?? 'Member (name unavailable)',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: _unblocking.contains(userId)
                              ? null
                              : () => _unblock(userId),
                          child: const Text('Unblock'),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}
