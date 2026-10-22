import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/song.dart';
import '../../services/lrc_tools.dart';
import '../../services/lyrics_edit_store.dart';
import '../../theme/app_theme.dart';

/// Create or revise the on-device lyric edit for one song (roadmap #21).
///
/// The sheet edits the RAW text: whatever is in the box is what gets stored and
/// shown, with no hidden normalization. Timestamped lines (LRC) unlock the
/// shift controls; plain text stores as-is. Import reads a `.lrc`/`.txt` file
/// straight off the device.
Future<void> showLyricsEditSheet(
  BuildContext context, {
  required Song song,
  required LyricsEditStore store,
  String? currentText,
  VoidCallback? onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kSurfaceColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => _LyricsEditSheet(
      song: song,
      store: store,
      initialText: currentText ?? '',
      onSaved: onSaved,
    ),
  );
}

class _LyricsEditSheet extends StatefulWidget {
  final Song song;
  final LyricsEditStore store;
  final String initialText;
  final VoidCallback? onSaved;

  const _LyricsEditSheet({
    required this.song,
    required this.store,
    required this.initialText,
    this.onSaved,
  });

  @override
  State<_LyricsEditSheet> createState() => _LyricsEditSheetState();
}

class _LyricsEditSheetState extends State<_LyricsEditSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  bool _busy = false;

  bool get _isLrc => LrcTools.isLrc(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await widget.store.save(widget.song.id, _controller.text);
    if (mounted) {
      Navigator.of(context).pop();
      widget.onSaved?.call();
    }
  }

  Future<void> _removeEdit() async {
    setState(() => _busy = true);
    await widget.store.delete(widget.song.id);
    if (mounted) {
      Navigator.of(context).pop();
      widget.onSaved?.call();
    }
  }

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;
      setState(() {
        _controller.text = utf8.decode(bytes, allowMalformed: true);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not read that file on this device')));
      }
    }
  }

  void _shift(Duration delta) {
    setState(() {
      _controller.text = LrcTools.shiftTimestamps(_controller.text, delta);
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final hasEdit = widget.initialText.trim().isNotEmpty;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit lyrics',
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(widget.song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: Colors.white38, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Import .lrc / .txt',
                    onPressed: _busy ? null : _importFile,
                    icon: const Icon(Icons.file_open_rounded,
                        color: Colors.white70),
                  ),
                  IconButton(
                    tooltip: 'Save',
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.check_rounded, color: kBrandColor),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Text(_isLrc ? 'Timestamped (LRC)' : 'Plain text',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white30, fontSize: 11)),
                  const Spacer(),
                  if (_isLrc) ...[
                    TextButton(
                      onPressed: () => _shift(const Duration(milliseconds: -500)),
                      child: const Text('−0.5s'),
                    ),
                    TextButton(
                      onPressed: () => _shift(const Duration(milliseconds: 500)),
                      child: const Text('+0.5s'),
                    ),
                  ],
                  if (hasEdit)
                    TextButton(
                      onPressed: _busy ? null : _removeEdit,
                      child: const Text('Remove edit',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: GoogleFonts.jetBrainsMono(
                      color: Colors.white, fontSize: 12.5, height: 1.5),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: kCardColor,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    hintText:
                        'Paste or type lyrics here.\n\n'
                        'Lines like [01:23.45] text are treated as synced.',
                    hintStyle: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white24, fontSize: 12.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
