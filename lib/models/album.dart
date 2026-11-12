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

  /// When the server first saw the album (Subsonic `created`), if reported.
  final DateTime? added;

  /// Record label (OpenSubsonic `recordLabels[0]`), if reported.
  final String? label;

  /// Lower-cased OpenSubsonic `releaseTypes` (album, single, ep, compilation...).
  final List<String> releaseTypes;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.year,
    required this.gradientColors,
    required this.songIds,
    this.artwork,
    this.added,
    this.label,
    this.releaseTypes = const [],
  });
}
