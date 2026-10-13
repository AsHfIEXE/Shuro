import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../state/player_controller.dart';

/// Rebuilds its subtree every frame *while playing*, handing it the true
/// clock-based playback position. Use around small pieces that need
/// smooth motion (progress ring, mini-player bar) — everything else can
/// keep listening to PlayerController's ~1 Hz updates. The ticker is
/// muted while paused, so it costs nothing when nothing is moving.
class SmoothPositionBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, PlayerController player, Duration position, double progress) builder;
  const SmoothPositionBuilder({super.key, required this.builder});

  @override
  State<SmoothPositionBuilder> createState() => _SmoothPositionBuilderState();
}

class _SmoothPositionBuilderState extends State<SmoothPositionBuilder> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final shouldRun = player.isPlaying;
    if (_ticker.muted == shouldRun) _ticker.muted = !shouldRun;
    return widget.builder(context, player, player.position, player.progress);
  }
}
