import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/build_from_mode.dart';
import '../models/song.dart';
import '../screens/now_playing/queue_screen.dart';
import '../services/shuro_pulse.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'page_transitions.dart';

/// The per-track "Build from this" sheet — radiates [seed] out into a full
/// queue using one of [BuildFromMode]'s rules, then starts playing it.
void showBuildFromThisSheet(BuildContext context, Song seed) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _BuildFromThisSheet(seed: seed),
  );
}

class _BuildFromThisSheet extends StatelessWidget {
  final Song seed;
  const _BuildFromThisSheet({required this.seed});

  void _run(BuildContext context, BuildFromMode mode) {
    final appState = context.read<AppState>();
    final player = context.read<PlayerController>();
    final queue = ShuroPulse.buildFrom(seed, mode, appState, targetLength: 20);
    player.playSong(seed, queue: queue);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Building "${mode.label}" from "${seed.title}"…'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'Queue', onPressed: () => Navigator.of(context).push(risingRoute(const QueueScreen()))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Build from "${seed.title}"',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Shuro will turn this one track into a full queue.',
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            for (final mode in BuildFromMode.values)
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded, color: kBrandColor, size: 20),
                title: Text(mode.label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(mode.description, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
                onTap: () => _run(context, mode),
              ),
          ],
        ),
      ),
    );
  }
}
