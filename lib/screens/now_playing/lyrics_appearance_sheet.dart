import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../state/appearance_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/click_region.dart';

/// Board: "Lyrics - tools and states" -> Appearance card (440 wide, #111723,
/// 20 radius). Everything applies the moment it moves; the lyrics screen
/// listens to the same [AppearanceSettings].
Future<void> showLyricsAppearanceSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => const Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.all(16),
      child: _AppearanceCard(),
    ),
  );
}

const Color kLyricsPanel = Color(0xFF111723);
const Color kLyricsLabel = Color(0xFF8B93A7);

TextStyle _t(double size, FontWeight w, Color c, {double? ls}) =>
    GoogleFonts.getFont(currentFontFamily,
        fontSize: size, fontWeight: w, color: c, letterSpacing: ls);

/// Shared card chrome for the lyrics tool panels (appearance, sync, edit).
class LyricsPanel extends StatelessWidget {
  const LyricsPanel({
    super.key,
    required this.label,
    required this.child,
    this.width = 440,
  });

  final String label;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Material(
        color: kLyricsPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      _t(11, FontWeight.w700, kLyricsLabel, ls: 1.0)),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppearanceSettings>();
    return LyricsPanel(
      label: 'APPEARANCE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('Text size',
                    style: _t(14, FontWeight.w600, const Color(0xFFE8E8F0)))),
            Text('${(a.lyricsFontScale * 100).round()}%',
                style: _t(13, FontWeight.w500, const Color(0xFF9AA3B5))),
          ]),
          const SizedBox(height: 10),
          _GradientSlider(
            value: a.lyricsFontScale,
            min: 0.85,
            max: 1.5,
            onChanged: a.setLyricsFontScale,
          ),
          const SizedBox(height: 22),
          _Row(
            'Alignment',
            _Segmented<bool>(
              options: const [(false, 'Left'), (true, 'Centre')],
              value: a.lyricsAlignCenter,
              onChanged: a.setLyricsAlignCenter,
            ),
          ),
          const SizedBox(height: 14),
          _Row(
            'Highlight',
            _Segmented<LyricsHighlight>(
              options: const [
                (LyricsHighlight.word, 'Word'),
                (LyricsHighlight.line, 'Line')
              ],
              value: a.lyricsHighlight,
              onChanged: a.setLyricsHighlight,
            ),
          ),
          const SizedBox(height: 14),
          _Row(
            'Glow on the sung line',
            LyricsSwitch(value: a.lyricsGlow, onChanged: a.setLyricsGlow),
          ),
          const SizedBox(height: 18),
          // Shuro's lyric sources carry one language, so this stays off and
          // disabled rather than pretending to translate.
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Show translation',
                      style: _t(14, FontWeight.w600, const Color(0xFFE8E8F0))),
                  const SizedBox(height: 2),
                  Text('English · under each line',
                      style: _t(12, FontWeight.w400, kLyricsLabel)),
                ],
              ),
            ),
            const Opacity(
                opacity: 0.5, child: LyricsSwitch(value: false, onChanged: null)),
          ]),
          const SizedBox(height: 18),
          _Row(
            'Backdrop',
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.1)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(
                    child: Text('Artwork mesh',
                        style: _t(13, FontWeight.w500,
                            const Color(0xFFE8E8F0)))),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 16, color: kLyricsLabel),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Text('Applies on every device and stays saved.',
              style: _t(12, FontWeight.w400, const Color(0xFF6F7890))),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.control);
  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(label,
                style: _t(14, FontWeight.w600, const Color(0xFFE8E8F0)))),
        SizedBox(
            width: label == 'Glow on the sung line' ? null : 200,
            child: Align(alignment: Alignment.centerRight, child: control)),
      ]);
}

/// 200 x 36 pill segmented control from the board.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        for (final o in options)
          Expanded(
            child: ClickRegion(
              onTap: () => onChanged(o.$1),
              child: AnimatedContainer(
                duration: ShuroMotion.fast,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: o.$1 == value
                      ? const Color(0xFF7C3AED)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(o.$2,
                    style: _t(
                        12,
                        FontWeight.w600,
                        o.$1 == value
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.65))),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 44 x 26 switch, 20 px knob (board "Switch on/off").
class LyricsSwitch extends StatelessWidget {
  const LyricsSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ClickRegion(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: ShuroMotion.spring,
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF7C3AED)
              : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Container(
          width: 20,
          height: 20,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// 4 px track with the pink-to-violet fill and a 16 px white knob.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
      void set(double dx) {
        final f = (dx / w).clamp(0.0, 1.0);
        // 5 % steps.
        final v = min + f * (max - min);
        onChanged((v * 20).round() / 20);
      }

      return ClickRegion(
        onTapDown: (d) => set(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => set(d.localPosition.dx),
        child: SizedBox(
          height: 24,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              height: 4,
              width: w * t,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF8FB8), Color(0xFFA78BFA)]),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Positioned(
              left: (w - 16) * t,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          ]),
        ),
      );
    });
  }
}
