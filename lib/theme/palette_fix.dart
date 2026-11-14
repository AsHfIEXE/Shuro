import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Guarantees the backdrop always has *some* chroma. Low-saturation covers
/// (B&W, muted) get a tasteful accent injection instead of gray smoke.
List<Color> spicyPalette(List<Color> raw) {
  if (raw.isEmpty) return kBrandGradient;
  var maxSat = 0.0;
  for (final c in raw) {
    final s = HSVColor.fromColor(c).saturation;
    if (s > maxSat) maxSat = s;
  }
  if (maxSat >= 0.22) return raw; // already colourful
  final t = (0.22 - maxSat) / 0.22; // 0..1 how gray it is
  return [
    for (var i = 0; i < raw.length; i++)
      Color.lerp(raw[i], kBrandGradient[i % kBrandGradient.length],
          0.35 + 0.4 * t)!,
  ];
}
