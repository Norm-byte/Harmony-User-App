import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/event_service.dart';
import '../services/home_speaker_state.dart';

class HomeSpeakerOverlay extends StatelessWidget {
  const HomeSpeakerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EventService>(
      builder: (context, eventService, _) {
        if (eventService.isEventActive) {
          return const SizedBox.shrink();
        }

        return AnimatedBuilder(
          animation: homeSpeakerUiStateNotifier,
          builder: (context, __) {
            final homeSpeakerState = homeSpeakerUiStateNotifier.value;

            if (!homeSpeakerState.visible) {
              return const SizedBox.shrink();
            }

            return Align(
              alignment: Alignment.topRight,
              child: SafeArea(
                minimum: const EdgeInsets.only(top: 12, right: 12),
                child: _HomeSpeakerButton(muted: homeSpeakerState.muted),
              ),
            );
          },
        );
      },
    );
  }
}

class _HomeSpeakerButton extends StatefulWidget {
  final bool muted;

  const _HomeSpeakerButton({required this.muted});

  @override
  State<_HomeSpeakerButton> createState() => _HomeSpeakerButtonState();
}

class _HomeSpeakerButtonState extends State<_HomeSpeakerButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () {
        if (mounted) setState(() => _pressed = false);
      },
      onTapUp: (_) {
        if (mounted) setState(() => _pressed = false);
      },
      onTap: () async {
        final Future<void> Function()? toggle =
            homeSpeakerToggleCallback;
        if (toggle != null) {
          await toggle();
        }
      },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _pressed
                ? Colors.black.withOpacity(0.52)
                : Colors.black.withOpacity(0.34),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: Colors.white70,
            size: 22,
          ),
        ),
      ),
    );
  }
}
