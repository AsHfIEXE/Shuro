import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/song.dart';
import '../../services/lrc_tools.dart';
import '../../services/lyrics_edit_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/click_region.dart';
import 'lyrics_appearance_sheet.dart' show LyricsPanel;

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
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
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

  Widget _pill(String label, VoidCallback? onTap) => ClickRegion(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label,
              style: GoogleFonts.getFont(currentFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE8E8F0))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final hasEdit = widget.initialText.trim().isNotEmpty;
    final style = GoogleFonts.getFont(currentFontFamily);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: LyricsPanel(
          label: 'EDIT LYRICS',
          width: 436,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(0, -8),
                child: Text('${widget.song.title} · ${widget.song.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE8E8F0))),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_isLrc ? 'Timestamped (LRC)' : 'Plain text',
                    style: style.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6EE7B7))),
              ),
              const SizedBox(height: 14),
              Container(
                height: 210,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  onChanged: (_) => setState(() {}),
                  textAlignVertical: TextAlignVertical.top,
                  style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFB4BBCB), fontSize: 12, height: 1.6),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    hintText: 'Paste or type lyrics here.\n\n'
                        'Lines like [01:23.45] text are treated as synced.',
                    hintStyle: style.copyWith(
                        color: Colors.white24, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_isLrc) ...[
                  _pill('−0.5 s',
                      () => _shift(const Duration(milliseconds: -500))),
                  _pill('+0.5 s',
                      () => _shift(const Duration(milliseconds: 500))),
                ],
                _pill('Import .lrc', _busy ? null : _importFile),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                ClickRegion(
                  onTap: _busy ? null : _save,
                  child: Container(
                    height: 34,
                    width: 120,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Text('Save',
                        style: style.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
                const Spacer(),
                if (hasEdit)
                  ClickRegion(
                    onTap: _busy ? null : _removeEdit,
                    child: Text('Remove edit',
                        style: style.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFCA5A5))),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
