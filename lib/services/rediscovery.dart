import '../models/song.dart';

/// Local, explainable "you liked this once" suggestions.
///
/// There is no server telemetry here and no scoring model: every rule reads
/// state the app already persists (favourites, listening history) and can be
/// described to the user in one sentence. Anything that cannot be established
/// is left out rather than guessed.
class Rediscovery {
  const Rediscovery._();

  /// How many of the most recent plays count as "recent". Favourites that
  /// fall outside this window are the ones worth resurfacing.
  static const int defaultRecentWindow = 40;

  /// Favourites the user has not played within [recentWindow] plays.
  ///
  /// Order follows the library so the shelf looks deliberate rather than
  /// random. With no history at all, every favourite qualifies — which is
  /// correct: nothing has been played recently.
  static List<Song> forgottenFavourites({
    required List<Song> library,
    required Set<String> favouriteIds,
    required List<String> history,
    int limit = 12,
    int recentWindow = defaultRecentWindow,
  }) {
    if (favouriteIds.isEmpty) return const [];

    final recent = history.take(recentWindow).toSet();
    final result = <Song>[];
    for (final song in library) {
      if (!favouriteIds.contains(song.id)) continue;
      if (recent.contains(song.id)) continue;
      result.add(song);
      if (result.length >= limit) break;
    }
    return result;
  }
}
