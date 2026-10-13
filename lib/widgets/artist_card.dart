import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/artist.dart';
import '../theme/app_theme.dart';
import 'artist_actions_sheet.dart';
import 'artwork_thumb.dart';

/// Circular artist card for Library > Artists and Search. Same sizing
/// approach as AlbumCard — wrap in a SizedBox for a horizontal rail, or use
/// directly inside a GridView cell.
class ArtistCard extends StatelessWidget {
  final Artist artist;
  final VoidCallback onTap;

  const ArtistCard({super.key, required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showArtistActionsSheet(context, artist);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ArtworkThumb(
              gradientColors: artist.gradientColors,
              artwork: artist.artwork,
              radius: 999,
              icon: Icons.person_rounded,
              iconSize: 34,
            ),
          ),
          const SizedBox(height: 8),
          Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
