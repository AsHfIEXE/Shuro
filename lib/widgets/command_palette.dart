import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// One runnable action in the desktop command palette.
class CommandPaletteEntry {
  final String label;

  /// Shortcut hint shown on the right, e.g. `Ctrl+L`. Purely informational:
  /// the palette never binds keys itself.
  final String? hint;

  /// Grouping heading, e.g. `Playback`, `Go to`.
  final String section;

  final VoidCallback run;

  const CommandPaletteEntry({
    required this.label,
    required this.section,
    required this.run,
    this.hint,
  });
}

/// Desktop command palette (Ctrl+Shift+P).
///
/// Keyboard model: type to filter, Up/Down to move, Enter to run, Esc to close.
/// Mouse works too. It is a launcher only — every entry closes over an existing
/// action, so there is no second code path to keep in sync.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<CommandPaletteEntry> commands,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) => _CommandPalette(commands: commands),
  );
}

class _CommandPalette extends StatefulWidget {
  final List<CommandPaletteEntry> commands;

  const _CommandPalette({required this.commands});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  String _query = '';
  int _active = 0;

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<CommandPaletteEntry> get _filtered {
    if (_query.isEmpty) return widget.commands;
    final q = _query.toLowerCase();
    return widget.commands
        .where((c) =>
            c.label.toLowerCase().contains(q) ||
            c.section.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _move(int delta) {
    final items = _filtered;
    if (items.isEmpty) return;
    setState(() {
      _active = (_active + delta).clamp(0, items.length - 1);
    });
    _revealActive();
  }

  void _revealActive() {
    if (!_scroll.hasClients) return;
    // Rows are a fixed 44 px; keep the active one inside the viewport.
    const rowHeight = 44.0;
    final target = (_active * rowHeight).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    final visibleTop = _scroll.offset;
    final visibleBottom = visibleTop + _scroll.position.viewportDimension;

    if (target < visibleTop) {
      _scroll.jumpTo(target);
    } else if (target + rowHeight > visibleBottom) {
      _scroll.jumpTo(target + rowHeight - _scroll.position.viewportDimension);
    }
  }

  void _run(CommandPaletteEntry entry) {
    Navigator.of(context).pop();
    // Let the dialog finish dismissing before the action touches routes/state.
    WidgetsBinding.instance.addPostFrameCallback((_) => entry.run());
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 96, left: 32, right: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowDown) {
              _move(1);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowUp) {
              _move(-1);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter) {
              if (items.isNotEmpty) _run(items[_active]);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Material(
            color: kCardColor,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            size: 18, color: Colors.white38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _fieldFocus,
                            autofocus: true,
                            cursorColor: kBrandColor,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Type a command…',
                              hintStyle: GoogleFonts.getFont(currentFontFamily,
                                  color: Colors.white30, fontSize: 14),
                            ),
                            onChanged: (value) => setState(() {
                              _query = value.trim();
                              _active = 0;
                            }),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('Esc',
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: Colors.white38, fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.06)),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text('No matching command',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: Colors.white30, fontSize: 13)),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 380),
                      child: ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final entry = items[i];
                          final active = i == _active;
                          final showHeader =
                              i == 0 || items[i - 1].section != entry.section;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showHeader)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 10, 16, 4),
                                  child: Text(entry.section.toUpperCase(),
                                      style: GoogleFonts.getFont(
                                          currentFontFamily,
                                          color: Colors.white30,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8)),
                                ),
                              SizedBox(
                                height: 44,
                                child: Material(
                                  color: active
                                      ? kBrandColor.withValues(alpha: 0.16)
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _run(entry),
                                    onHover: (hovering) {
                                      if (hovering && _active != i) {
                                        setState(() => _active = i);
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              entry.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.getFont(
                                                currentFontFamily,
                                                color: active
                                                    ? Colors.white
                                                    : Colors.white70,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          if (entry.hint != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 12),
                                              child: Text(entry.hint!,
                                                  style: GoogleFonts.getFont(
                                                      currentFontFamily,
                                                      color: Colors.white24,
                                                      fontSize: 10.5)),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
