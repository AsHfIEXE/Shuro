import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/smart_playlist_preset.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_transitions.dart';
import '../playlist/playlist_detail_screen.dart';

/// Smart Playlists are live queries, not fixed lists — tapping one pins a
/// lightweight reference into AppState.playlists (so it shows up in
/// Library too) and opens it; ShuroPulse recomputes its actual tracks
/// every time it's opened. See Playlist.smartPreset.
class SmartPlaylistsScreen extends StatelessWidget {
  const SmartPlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        title: Text('Smart Playlists', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              'Mixes that re-build themselves from your library every time you open them — nothing to maintain.',
              style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
            ),
          ),
          for (final preset in SmartPlaylistPreset.values)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: kBrandGradient)),
                child: Icon(preset.icon, color: Colors.white),
              ),
              title: Text(preset.label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(preset.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: kMutedTextColor),
              onTap: () {
                final playlist = appState.createSmartPlaylist(preset);
                Navigator.of(context).push(drillDownRoute(PlaylistDetailScreen(playlist: playlist)));
              },
            ),
        ],
      ),
    );
  }
}
