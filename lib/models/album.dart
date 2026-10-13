import 'package:flutter/material.dart';

class Album {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final int year;
  final List<Color> gradientColors;
  final ImageProvider? artwork;
  final List<String> songIds;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.year,
    required this.gradientColors,
    required this.songIds,
    this.artwork,
  });
}
