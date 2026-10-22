import 'package:flutter/foundation.dart';

/// Audiobookshelf is intentionally modelled separately from music. A book is
/// playable as a whole timeline; a podcast show is not playable and owns
/// independently playable episodes.
enum SpokenMediaType { book, podcast }

@immutable
class SpokenLibrary {
  const SpokenLibrary(
      {required this.id, required this.name, required this.type});
  final String id;
  final String name;
  final SpokenMediaType type;
}

@immutable
class SpokenItem {
  const SpokenItem({
    required this.id,
    required this.libraryId,
    required this.type,
    required this.title,
    required this.creator,
    required this.duration,
    this.description = '',
    this.coverUrl,
    this.progressSeconds = 0,
    this.episodes = const [],
  });
  final String id;
  final String libraryId;
  final SpokenMediaType type;
  final String title;
  final String creator;
  final Duration duration;
  final String description;
  final String? coverUrl;
  final double progressSeconds;
  final List<SpokenEpisode> episodes;

  bool get isBook => type == SpokenMediaType.book;
  double get progress => duration.inMilliseconds == 0
      ? 0
      : (progressSeconds / duration.inSeconds).clamp(0, 1).toDouble();
}

@immutable
class SpokenEpisode {
  const SpokenEpisode({
    required this.id,
    required this.title,
    required this.duration,
    this.publishedAt,
    this.description = '',
    this.progressSeconds = 0,
  });
  final String id;
  final String title;
  final Duration duration;
  final DateTime? publishedAt;
  final String description;
  final double progressSeconds;
}
