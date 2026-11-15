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

/// A chapter marker inside an audiobook's single timeline (seconds from the
/// item start). Used for chapter jumps and the end-of-chapter sleep timer.
@immutable
class SpokenChapter {
  const SpokenChapter(
      {required this.id, required this.start, required this.end, required this.title});
  final int id;
  final double start;
  final double end;
  final String title;
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
    this.chapters = const [],
    this.seriesNames = const [],
    this.isFinished = false,
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
  final List<SpokenChapter> chapters;

  /// Series names from the item's metadata (ABS maintains these on scan;
  /// books can belong to several series).
  final List<String> seriesNames;

  /// The server's own finished flag for this user, if it reports one.
  final bool isFinished;

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
    this.fileIndex = 0,
  });
  final String id;
  final String title;
  final Duration duration;
  final DateTime? publishedAt;
  final String description;
  final double progressSeconds;

  /// The item's audio-file slot this episode plays from (ABS
  /// /api/items/<id>/file/<index>).
  final int fileIndex;
}
