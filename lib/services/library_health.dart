import '../models/song.dart';

/// One row of the health report: what is wrong, and which tracks show it.
class HealthIssue {
  /// Stable id used for ordering and for tests.
  final String id;

  /// Short, boring title: "Missing artwork".
  final String title;

  /// What the finding means, in the app's own evidence language.
  final String detail;

  final List<Song> songs;

  const HealthIssue({
    required this.id,
    required this.title,
    required this.detail,
    required this.songs,
  });

  int get count => songs.length;
}

/// Read-only analysis of the songs the app already holds.
///
/// Nothing here writes to the library, the server, or the filesystem: it counts
/// what the current [Song] objects can actually prove. A field the app never
/// receives is reported as missing rather than guessed at, and duplicate
/// detection only flags rows that agree on artist *and* title *and* duration —
/// two different mixes of the same song are not a duplicate.
class LibraryHealthReport {
  final int totalSongs;

  /// Ordered by severity: problems a listener notices first come first.
  final List<HealthIssue> issues;

  const LibraryHealthReport({required this.totalSongs, required this.issues});

  bool get isEmpty => issues.isEmpty;

  int get totalIssues => issues.fold(0, (sum, issue) => sum + issue.count);

  static const empty = LibraryHealthReport(totalSongs: 0, issues: []);

  factory LibraryHealthReport.build(List<Song> songs) {
    if (songs.isEmpty) return LibraryHealthReport.empty;

    final noArtwork = <Song>[
      for (final song in songs)
        if (song.artwork == null) song,
    ];

    final noArtist = <Song>[
      for (final song in songs)
        if (song.artist.trim().isEmpty ||
            song.artist.trim().toLowerCase() == 'unknown artist')
          song,
    ];

    final noAlbum = <Song>[
      for (final song in songs)
        if (song.albumId.trim().isEmpty) song,
    ];

    final noDuration = <Song>[
      for (final song in songs) if (song.duration == Duration.zero) song,
    ];

    // Exact duplicates only: same artist, same title, same length.
    final buckets = <String, List<Song>>{};
    for (final song in songs) {
      final key = '${song.artist.toLowerCase()}|'
          '${song.title.toLowerCase()}|'
          '${song.duration.inSeconds}';
      (buckets[key] ??= <Song>[]).add(song);
    }
    final duplicates = <Song>[
      for (final bucket in buckets.values)
        if (bucket.length > 1) ...bucket,
    ];

    final issues = <HealthIssue>[
      if (noArtwork.isNotEmpty)
        HealthIssue(
          id: 'artwork',
          title: 'Missing artwork',
          detail: 'The track carries no artwork the app can display.',
          songs: noArtwork,
        ),
      if (noArtist.isNotEmpty)
        HealthIssue(
          id: 'artist',
          title: 'Missing artist tag',
          detail: 'Artist is blank or "Unknown Artist", so grouping and '
              'search will be unreliable.',
          songs: noArtist,
        ),
      if (noAlbum.isNotEmpty)
        HealthIssue(
          id: 'album',
          title: 'Missing album tag',
          detail: 'No album id, so the track cannot appear under an album.',
          songs: noAlbum,
        ),
      if (noDuration.isNotEmpty)
        HealthIssue(
          id: 'duration',
          title: 'Unknown duration',
          detail: 'The server or file reported no length, so seeking and '
              'gapless decisions have nothing to work with.',
          songs: noDuration,
        ),
      if (duplicates.isNotEmpty)
        HealthIssue(
          id: 'duplicates',
          title: 'Exact duplicates',
          detail: 'Same artist, same title and same length. Different mixes '
              'and remasters are never grouped.',
          songs: duplicates,
        ),
    ];

    return LibraryHealthReport(totalSongs: songs.length, issues: issues);
  }
}
