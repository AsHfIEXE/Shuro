import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';
import 'artwork_thumb.dart';

/// Multi-select song picker for adding tracks to a playlist.
class AddSongsSheet extends StatefulWidget {
  final List<Song> available;
  final void Function(List<Song>) onAdd;

  const AddSongsSheet({super.key, required this.available, required this.onAdd});

  @override
  State<AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<AddSongsSheet> {
  String _query = '';
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.available
        : widget.available
            .where((s) =>
                s.title.toLowerCase().contains(_query) ||
                s.artist.toLowerCase().contains(_query))
            .toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search songs…',
                hintStyle: GoogleFonts.getFont(currentFontFamily, color: Colors.white24, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                filled: true,
                fillColor: kCardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text('No matches', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white38)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final song = filtered[i];
                      final checked = _selected.contains(song.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(song.id);
                          } else {
                            _selected.remove(song.id);
                          }
                        }),
                        title: Text(song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13.5)),
                        subtitle: Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily, color: Colors.white38, fontSize: 12)),
                        secondary: ArtworkThumb(gradientColors: song.gradientColors, artwork: song.artwork, size: 40, radius: 6),
                        activeColor: kBrandColor,
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Add ${_selected.length} song${_selected.length == 1 ? '' : 's'}'),
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final picked = widget.available
                              .where((s) => _selected.contains(s.id))
                              .toList();
                          Navigator.of(context).pop();
                          widget.onAdd(picked);
                        },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
