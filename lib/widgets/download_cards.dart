import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/song.dart';
import '../../services/download_service.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import 'artwork_thumb.dart';

/// The downloaded library as cards: artwork plus title/artist metadata, an
/// explicit selection mode for clearing chosen items, and a clear-all with
/// confirmation. Playback stays one tap away; selection is long-press, the
/// same gesture the rest of the app already uses for actions.
class DownloadCardsSection extends StatefulWidget {
  const DownloadCardsSection({super.key});

  @override
  State<DownloadCardsSection> createState() => _DownloadCardsSectionState();
}

class _DownloadCardsSectionState extends State<DownloadCardsSection> {
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _clearSelected() async {
    final downloads = context.read<DownloadService>();
    final ids = List<String>.of(_selected);
    setState(() => _selected.clear());
    for (final id in ids) {
      await downloads.remove(id);
    }
  }

  Future<void> _clearAll(int total) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Remove all $total downloads?',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 15)),
        content: Text(
            'The files are deleted from this device. Nothing on your server '
            'is affected.',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white60, fontSize: 12.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    final downloads = context.read<DownloadService>();
    setState(() => _selected.clear());
    for (final song in downloads.songs) {
      await downloads.remove(song.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final songs = downloads.songs;

    if (songs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'Nothing is downloaded yet. Long-press any song and choose '
            'Download to keep it on this device.',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white38, fontSize: 12.5, height: 1.5),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selecting
                      ? '${_selected.length} of ${songs.length} selected'
                      : '${songs.length} on this device',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: _selecting ? kBrandColor : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (_selecting) ...[
                TextButton(
                  onPressed: _selected.length == songs.length
                      ? () => setState(() => _selected.clear())
                      : () => setState(
                          () => _selected.addAll(songs.map((s) => s.id))),
                  child: Text(
                      _selected.length == songs.length ? 'Deselect all' : 'Select all',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white60, fontSize: 12)),
                ),
                TextButton(
                  onPressed: _clearSelected,
                  child: Text('Remove ${_selected.length}',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.redAccent, fontSize: 12)),
                ),
              ] else
                TextButton(
                  onPressed: () => _clearAll(songs.length),
                  child: Text('Remove all',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white38, fontSize: 12)),
                ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 320,
            mainAxisExtent: 92,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: songs.length,
          itemBuilder: (context, i) => _DownloadCard(
            song: songs[i],
            selecting: _selecting,
            selected: _selected.contains(songs[i].id),
            onTap: () {
              if (_selecting) {
                _toggle(songs[i].id);
              } else {
                context
                    .read<PlayerController>()
                    .playOrToggle(songs[i], queue: songs);
              }
            },
            onLongPress: () => _toggle(songs[i].id),
          ),
        ),
      ],
    );
  }
}

class _DownloadCard extends StatelessWidget {
  final Song song;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _DownloadCard({
    required this.song,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? kBrandColor.withValues(alpha: 0.14)
          : kCardColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ArtworkThumb(
                  gradientColors: song.gradientColors,
                  artwork: song.artwork,
                  size: 64,
                  radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white38, fontSize: 11.5)),
                    const SizedBox(height: 3),
                    Text(
                      song.audioInfo.hasFormat
                          ? '${song.audioInfo.format} · ${song.audioInfo.bitrateKbps} kbps'
                          : 'Saved on this device',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white24, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              if (selecting)
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? kBrandColor : Colors.white30,
                )
              else
                const Icon(Icons.offline_pin_rounded,
                    size: 18, color: Colors.white30),
            ],
          ),
        ),
      ),
    );
  }
}
