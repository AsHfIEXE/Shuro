import 'package:flutter/material.dart';

class Artist {
  final String id;
  final String name;
  final List<Color> gradientColors;
  final ImageProvider? artwork;
  final List<String> albumIds;
  final List<String> topSongIds;

  const Artist({
    required this.id,
    required this.name,
    required this.gradientColors,
    required this.albumIds,
    required this.topSongIds,
    this.artwork,
  });
}
