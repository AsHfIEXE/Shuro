import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/state_views.dart';

const _kPromptSuggestions = [
  'Something calm for studying',
  'High energy for a workout',
  'Songs I haven\'t heard in a while',
  'Fresh stuff from my library',
  'My favorites, remixed',
];

/// "Build with Shuro" — a short free-text prompt turned into a playlist.
/// ShuroPulse.songsForPrompt does real (if simple) intent detection against
/// your own library rather than calling out to anything — see its
/// doc-comment for exactly what it matches on.
class BuildWithShuroScreen extends StatefulWidget {
  const BuildWithShuroScreen({super.key});

  @override
  State<BuildWithShuroScreen> createState() => _BuildWithShuroScreenState();
}

class _BuildWithShuroScreenState extends State<BuildWithShuroScreen> {
  final _controller = TextEditingController();
  List<Song>? _result;
  String? _resultPrompt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _build([String? prompt]) {
    final text = (prompt ?? _controller.text).trim();
    if (text.isEmpty) return;
    final appState = context.read<AppState>();
    setState(() {
      _controller.text = text;
      _resultPrompt = text;
      _result = ShuroPulse.songsForPrompt(text, appState, limit: 20);
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final appState = context.read<AppState>();
    final result = _result;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        title: Text('Build with Shuro', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Describe what you want to hear', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Shuro builds it from your own library.', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _controller,
                    onSubmitted: _build,
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. "something calm for studying"',
                      hintStyle: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13),
                      filled: true,
                      fillColor: kCardColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded, color: kBrandColor),
                        onPressed: () => _build(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _kPromptSuggestions)
                        GestureDetector(
                          onTap: () => _build(s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: kCardColor, borderRadius: BorderRadius.circular(20)),
                            child: Text(s, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: kDividerColor),
            Expanded(
              child: result == null
                  ? const EmptyStateView(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Nothing built yet',
                      subtitle: 'Type a mood or pick a suggestion above.',
                    )
                  : result.isEmpty
                      ? const EmptyStateView(icon: Icons.search_off_rounded, title: "Couldn't find a good match", subtitle: 'Try a different phrase.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('${result.length} tracks for "$_resultPrompt"',
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      final playlist = appState.createPlaylist(
                                        _resultPrompt ?? 'Built with Shuro',
                                        songIds: result.map((s) => s.id).toList(),
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Saved "${playlist.name}" to your playlists'), behavior: SnackBarBehavior.floating),
                                      );
                                    },
                                    child: Text('Save as playlist', style: GoogleFonts.getFont(currentFontFamily, color: kBrandColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: result.length,
                                itemBuilder: (context, i) {
                                  final song = result[i];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                                    leading: ArtworkThumb(gradientColors: song.gradientColors, artwork: song.artwork, size: 46, radius: 8),
                                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                                    subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
                                    onTap: () => player.playSong(song, queue: result),
                                  );
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: () => player.playSong(result.first, queue: result),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kBrandColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: Text('Play all', style: GoogleFonts.getFont(currentFontFamily, fontSize: 14, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
