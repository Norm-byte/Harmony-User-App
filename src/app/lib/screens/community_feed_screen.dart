import 'package:flutter/material.dart';

import 'community_room_screen.dart';

class CommunityFeedScreen extends StatelessWidget {
  final Map<String, dynamic>? preselectedVaultImage;
  final bool showAppBar;

  const CommunityFeedScreen({
    super.key,
    this.preselectedVaultImage,
    this.showAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    return CommunityRoomScreen(
      preselectedVaultImage: preselectedVaultImage,
      showAppBar: showAppBar,
    );
  }
}
