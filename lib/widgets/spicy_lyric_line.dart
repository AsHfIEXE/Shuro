import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../state/appearance_settings.dart';

/// One lyric line, Spicy-style: the sung line is crisp white + accent glow;
/// every other line fades AND defocuses with distance (ImageFiltered blur
/// animated over 320 ms on line change, then idle — cheap).
///
/// Word mode: pass [words] + [progress] (0..1 within the line) and the fill
/// sweeps left→right with a feathered edge. Line mode: omit [words].
class SpicyLyricLine extends StatelessWidget {
  final String text;
  final List<SpicyWord>? words;
  final bool active;
  final int distance; // |index - activeIndex|
  final double progress; // 0..1, only used when active && words != null
  final TextStyle baseStyle; // font/size from the screen's existing logic
  final LyricsHighlight mode;
  final bool glow;
  final bool alignCenter;
  final Color accent;

  const SpicyLyricLine({
    super.key,
    required this.text,
    required this.active,
    required this.distance,
    required this.baseStyle,
    this.words,
    this.progress = 0,
    this.mode = LyricsHighlight.word,
    this.glow = true,
    this.alignCenter = true,
    this.accent = const Color(0xFFFF6B9D),
  });

  static const Color _lit = Color(0xFFF4F4F8);
  static const Color _dim = Color(0xFF9A9AA6);

  @override
  Widget build(BuildContext context) {
    // Distance → defocus. Cap so far lines don't cost more than near ones.
    final sigma = active ? 0.0 : (distance * 1.2).clamp(0.0, 5.0);
    final opacity = active ? 1.0 : (1.0 - distance * 0.14).clamp(0.18, 0.75);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 320),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: sigma, end: sigma),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          builder: (_, s, child) => ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s),
            child: child,
          ),
          child: AnimatedScale(
            scale: active ? 1.045 : 1.0,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            child: _content(),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final style = baseStyle.copyWith(
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      color: active ? _lit : _dim,
      shadows: active && glow
          ? [Shadow(color: accent.withValues(alpha: 0.55), blurRadius: 22)]
          : null,
    );

    if (active &&
        mode == LyricsHighlight.word &&
        words != null &&
        words!.isNotEmpty) {
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) {
          final p = progress.clamp(0.0, 1.0);
          const f = 0.03; // feather width
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [_lit, _lit, _dim, _dim],
            stops: [
              0.0,
              (p - f).clamp(0.0, 1.0),
              (p + f).clamp(0.0, 1.0),
              1.0,
            ],
          ).createShader(rect);
        },
        child: Text(
          words!.map((w) => w.text).join(' '),
          textAlign: alignCenter ? TextAlign.center : TextAlign.start,
          style: style,
        ),
      );
    }

    return Text(text,
        textAlign: alignCenter ? TextAlign.center : TextAlign.start,
        style: style);
  }
}

class SpicyWord {
  final String text;
  final double start; // seconds
  final double end;
  const SpicyWord(this.text, this.start, this.end);
}
