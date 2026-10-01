import 'package:flutter/material.dart';

import '../services/user_service.dart';

Future<void> showCommunityBlockedUsersDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final blockedUsers = List<String>.from(UserService().blockedUsers)..sort();
        return AlertDialog(
          title: const Text('Blocked users'),
          content: SizedBox(
            width: 420,
            child: blockedUsers.isEmpty
                ? const Text('You have not blocked anyone.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: blockedUsers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final userId = blockedUsers[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(userId, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: TextButton(
                          onPressed: () async {
                            await UserService().unblockUser(userId);
                            setDialogState(() {});
                          },
                          child: const Text('Unblock'),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}
