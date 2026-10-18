import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app_info.dart';

/// MusicBrainz + Cover Art Archive lookups — **no API key, no user credential**.
///
/// Verified against MusicBrainz's own documentation (see
/// `_refs/musicbrainz_contract.md`): read-only lookups need no token, and the
/// binding requirements are a *non-generic* `User-Agent` and at most **one
/// request per second** per client. OAuth2 exists only for user-owned data
/// (collections, ratings, tags) and is not needed to enrich metadata or fetch
/// artwork — which is why this file has no auth at all.
///
/// Two consequences of the 1 req/s rule are built in rather than documented and
/// forgotten:
///
///  * every request goes through [_throttle], so a caller can't accidentally
///    hammer the service by looping;
///  * enrichment is written for **one track on demand**, not a library sweep.
///    The two-request path (search → recording lookup → release-group) costs
///    ~2 s per track by design; a whole-library pass would take hours and would
///    be the kind of bulk behaviour the contract warns about.
class MusicBrainzClient {
  MusicBrainzClient._();

  static const String _base = 'https://musicbrainz.org/ws/2';
  static const String _coverArtBase = 'https://coverartarchive.org';

  /// MusicBrainz requires a User-Agent that identifies the application, and
  /// recommends including a contact URL or email so they can reach the operator
  /// instead of blocking the IP. Adding a real contact here is the one change
  /// worth making before shipping: a generic UA is the documented way to get
  /// rate-limited or blocked.
  static final String userAgent = 'Shuro/$kAppVersion ( self-hosted Navidrome client )';

  /// Documented ceiling is one call per second; 1100 ms leaves headroom.
  static const Duration _minSpacing = Duration(milliseconds: 1100);
  static DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cache: a track's match is stable enough that re-asking within a session is
  /// pure waste of the shared rate budget.
  static final Map<String, MusicBrainzMatch?> _cache = {};
  static const int _cacheLimit = 200;

  static Future<void> _throttle() async {
    final wait = _lastRequestAt.add(_minSpacing).difference(DateTime.now());
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastRequestAt = DateTime.now();
  }

  /// Finds the best MusicBrainz recording for a track, and — when one exists —
  /// the release-group id needed for artwork.
  ///
  /// Returns null when nothing plausible matches, which is a normal outcome for
  /// a self-hosted library full of obscure releases, not an error.
  static Future<MusicBrainzMatch?> match({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
    String? musicBrainzId,
  }) async {
    final key = '${title.toLowerCase()}|${artist.toLowerCase()}|${musicBrainzId ?? ''}';
    if (_cache.containsKey(key)) return _cache[key];

    final result = musicBrainzId != null && musicBrainzId.isNotEmpty
        ? await _matchByMbid(musicBrainzId, title: title, artist: artist)
        : await _matchBySearch(title: title, artist: artist, album: album, duration: duration);

    if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[key] = result;
    return result;
  }

  static Future<MusicBrainzMatch?> _matchByMbid(String mbid, {required String title, required String artist}) async {
    // The library already told us which recording this is — no search needed,
    // just the release-group for artwork.
    final recording = await _getJson(Uri.parse('$_base/recording/$mbid?inc=release-groups+artist-credits&fmt=json'));
    if (recording == null) return null;
    return MusicBrainzMatch(
      recordingId: mbid,
      title: (recording['title'] as String?) ?? title,
      artist: _artistCredit(recording) ?? artist,
      score: 100,
      releaseGroupId: _firstReleaseGroupId(recording),
    );
  }

  static Future<MusicBrainzMatch?> _matchBySearch({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final query = buildSearchQuery(title: title, artist: artist, album: album);
    final uri = Uri.parse('$_base/recording?query=${Uri.encodeQueryComponent(query)}&limit=5&fmt=json');
    final body = await _getJson(uri);
    final recordings = body?['recordings'] as List<dynamic>?;
    if (recordings == null || recordings.isEmpty) return null;

    // MusicBrainz returns a relevance `score` (0-100). Take the best one, and
    // use duration only as a tie-breaker — it is the field most likely to differ
    // between a library file and the canonical release.
    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final raw in recordings) {
      if (raw is! Map<String, dynamic>) continue;
      final score = (raw['score'] as num?)?.toInt() ?? 0;
      final lengthMs = (raw['length'] as num?)?.toInt();
      final durationAgrees = duration == null || lengthMs == null || (lengthMs - duration.inMilliseconds).abs() < 8000;
      final effective = score + (durationAgrees ? 5 : 0);
      if (effective > bestScore) {
        bestScore = effective;
        best = raw;
      }
    }
    if (best == null) return null;

    final recordingId = best['id'] as String?;
    // The search response does not include release-group ids, so one lookup is
    // needed to get artwork. Skipped when the id is missing.
    String? releaseGroupId;
    if (recordingId != null) {
      releaseGroupId = await _firstReleaseGroupFor(recordingId);
    }

    return MusicBrainzMatch(
      recordingId: recordingId ?? '',
      title: (best['title'] as String?) ?? title,
      artist: _artistCredit(best) ?? artist,
      score: (best['score'] as num?)?.toInt() ?? 0,
      releaseGroupId: releaseGroupId,
    );
  }

  static Future<String?> _firstReleaseGroupFor(String recordingId) async {
    final body = await _getJson(Uri.parse('$_base/recording/$recordingId?inc=release-groups&fmt=json'));
    return _firstReleaseGroupId(body);
  }

  /// A Lucene query. Field-scoped and quoted so `artist:"The Weeknd"` matches
  /// as a phrase; values are escaped because a title containing a quote would
  /// otherwise produce a malformed query (and a 400 from MusicBrainz).
  ///
  /// Public because the query shape is the part worth asserting in a test.
  static String buildSearchQuery({required String title, required String artist, String? album}) {
    final parts = <String>['recording:"${escapeLucene(title)}"', 'artist:"${escapeLucene(artist)}"'];
    if (album != null && album.trim().isNotEmpty) parts.add('release:"${escapeLucene(album)}"');
    return parts.join(' AND ');
  }

  /// Escapes the two characters that would otherwise break out of a quoted
  /// Lucene phrase.
  static String escapeLucene(String value) => value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static String? _artistCredit(Map<String, dynamic> recording) {
    final credits = recording['artist-credit'] as List<dynamic>?;
    if (credits == null || credits.isEmpty) return null;
    final buffer = StringBuffer();
    for (final credit in credits) {
      if (credit is! Map<String, dynamic>) continue;
      buffer.write((credit['name'] as String?) ?? (credit['artist'] as Map<String, dynamic>?)?['name'] as String? ?? '');
      buffer.write((credit['joinphrase'] as String?) ?? '');
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String? _firstReleaseGroupId(Map<String, dynamic>? recording) {
    final groups = recording?['release-groups'] as List<dynamic>?;
    if (groups == null || groups.isEmpty) return null;
    for (final group in groups) {
      if (group is Map<String, dynamic>) {
        final id = group['id'] as String?;
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  /// Front cover art for a release-group, at the size the app actually displays.
  ///
  /// The Cover Art Archive serves artwork by release **or** release-group MBID
  /// without authentication; release-group is used here because it is what the
  /// recording lookup gives us, and it is the stable choice across pressings.
  static String? coverArtUrl(String? releaseGroupId, {int size = 500}) {
    if (releaseGroupId == null || releaseGroupId.isEmpty) return null;
    return '$_coverArtBase/release-group/$releaseGroupId/front-$size';
  }

  static Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    await _throttle();
    try {
      final response = await http.get(uri, headers: {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      if (response.statusCode == 404) return null; // no such entity — not an error
      if (response.statusCode != 200) return null;
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('json')) return null;
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // A lookup that can't complete is not worth failing a screen over: the
      // caller treats null as "nothing to enrich with".
      return null;
    }
  }
}

/// One MusicBrainz recording match, with the release-group id Cover Art Archive
/// needs. Deliberately small: the app only uses it to fill in a missing image or
/// to show the user what was found.
class MusicBrainzMatch {
  final String recordingId;
  final String title;
  final String artist;

  /// MusicBrainz's own relevance score, 0-100.
  final int score;
  final String? releaseGroupId;

  const MusicBrainzMatch({
    required this.recordingId,
    required this.title,
    required this.artist,
    required this.score,
    this.releaseGroupId,
  });

  String? get coverArtUrl => MusicBrainzClient.coverArtUrl(releaseGroupId);

  bool get hasArtwork => releaseGroupId != null;
}
