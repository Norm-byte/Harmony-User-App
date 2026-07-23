import 'package:flutter/material.dart';

class HomeSpeakerUiState {
  final bool visible;
  final bool muted;

  const HomeSpeakerUiState({
    required this.visible,
    required this.muted,
  });

  HomeSpeakerUiState copyWith({bool? visible, bool? muted}) {
    return HomeSpeakerUiState(
      visible: visible ?? this.visible,
      muted: muted ?? this.muted,
    );
  }
}

final ValueNotifier<HomeSpeakerUiState> homeSpeakerUiStateNotifier =
    ValueNotifier(
  const HomeSpeakerUiState(visible: false, muted: false),
);

Future<void> Function()? homeSpeakerToggleCallback;
