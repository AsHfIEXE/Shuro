import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'state_views.dart';

/// The lightweight "More like this / Less like this / Not interested"
/// feedback loop from the Discover rows — a few taps rather than a rating
/// scale, feeding straight into AppState.recordArtistFeedback (and from
/// there into ShuroPulse's affinity scoring).
class RecommendationFeedbackButton extends StatelessWidget {
  final String artistId;
  final String artistName;

  const RecommendationFeedbackButton({super.key, required this.artistId, required this.artistName});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return PopupMenuButton<String>(
      color: kCardColor,
      icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70, size: 18),
      onSelected: (value) {
        switch (value) {
          case 'more':
            appState.recordArtistFeedback(artistId, true);
            showSuccessSnackBar(context, 'Got it — more $artistName');
          case 'less':
            appState.recordArtistFeedback(artistId, false);
            showSuccessSnackBar(context, 'Got it — showing less of this');
          case 'not_interested':
            // One nudge, not two. This used to record the same negative feedback
            // twice for a single tap, double-counting -1.5 into the artist's
            // affinity score — so "not interested" hit twice as hard as
            // "less like this", which was never the intent.
            appState.recordArtistFeedback(artistId, false);
            showSuccessSnackBar(context, "Won't suggest this as much");
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'more', child: _row(Icons.thumb_up_rounded, 'More like this')),
        PopupMenuItem(value: 'less', child: _row(Icons.thumb_down_rounded, 'Less like this')),
        PopupMenuItem(value: 'not_interested', child: _row(Icons.block_rounded, 'Not interested')),
      ],
    );
  }

  Widget _row(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13)),
      ],
    );
  }
}
