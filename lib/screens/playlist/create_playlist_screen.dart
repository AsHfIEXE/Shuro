import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/playlist_collage_art.dart';

/// A proper playlist-creation flow: name, and a cover that's either a
/// user-picked photo or an auto-generated collage of the songs it starts
/// with — reachable directly from Library > Playlists, not just buried in
/// a song's "add to playlist" sheet.
class CreatePlaylistScreen extends StatefulWidget {
  final String? initialSongId;
  const CreatePlaylistScreen({super.key, this.initialSongId});

  @override
  State<CreatePlaylistScreen> createState() => _CreatePlaylistScreenState();
}

class _CreatePlaylistScreenState extends State<CreatePlaylistScreen> {
  final _nameController = TextEditingController();
  ImageProvider? _customArtwork;
  bool _picking = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    setState(() => _picking = true);
    final bytes = await context.read<AppState>().pickImageBytes();
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (bytes != null) _customArtwork = MemoryImage(bytes);
    });
  }

  void _create() {
    final name = _nameController.text.trim().isEmpty ? 'New Playlist' : _nameController.text.trim();
    final appState = context.read<AppState>();
    final playlist = appState.createPlaylist(
      name,
      artwork: _customArtwork,
      songIds: widget.initialSongId != null ? [widget.initialSongId!] : const [],
    );
    Navigator.of(context).pop(playlist);
  }

  @override
  Widget build(BuildContext context) {
    // A lightweight preview playlist so PlaylistCollageArt can render the
    // chosen photo, or a collage of the starting song, before it's saved.
    final previewPlaylist = Playlist(
      id: 'preview',
      name: _nameController.text,
      songIds: widget.initialSongId != null ? [widget.initialSongId!] : const [],
      artwork: _customArtwork,
    );

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        title: Text('New Playlist', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              GestureDetector(
                onTap: _picking ? null : _choosePhoto,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(width: 160, height: 160, child: PlaylistCollageArt(playlist: previewPlaylist, radius: 16)),
                    if (_picking) const CircularProgressIndicator(color: Colors.white),
                    if (!_picking)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: kBrandColor, shape: BoxShape.circle),
                          child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _picking ? null : _choosePhoto,
                child: Text('Choose photo', style: GoogleFonts.getFont(currentFontFamily, color: kBrandColor, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (_customArtwork != null)
                TextButton(
                  onPressed: () => setState(() => _customArtwork = null),
                  child: Text('Use auto collage instead', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Playlist name',
                  hintStyle: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 15),
                  filled: true,
                  fillColor: kCardColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _create,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  child: Text('Create Playlist', style: GoogleFonts.getFont(currentFontFamily, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
