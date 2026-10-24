import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../backend/audiobookshelf_api.dart';
import '../models/spoken_media.dart';
import '../services/app_persistence.dart';
import '../services/server_secret_store.dart';

@immutable
class AudiobookshelfConnection {
  const AudiobookshelfConnection({required this.url, required this.name});
  final String url;
  final String name;
}

/// Holds Audiobookshelf separately from Navidrome. No connection is assumed
/// to contain music; book and podcast libraries are discovered by mediaType.
class SpokenLibraryState extends ChangeNotifier {
  static const _configKey = 'audiobookshelf_connection_v1';
  static const _secretKey = 'audiobookshelf';
  AudiobookshelfConnection? connection;
  List<SpokenLibrary> libraries = const [];
  final Map<String, List<SpokenItem>> itemsByLibrary = {};
  bool loading = false;
  String? error;
  AudiobookshelfApi? _api;

  List<SpokenLibrary> get bookLibraries =>
      libraries.where((l) => l.type == SpokenMediaType.book).toList();
  List<SpokenLibrary> get podcastLibraries =>
      libraries.where((l) => l.type == SpokenMediaType.podcast).toList();

  Future<void> restore() async {
    final store = await AppPersistence.load();
    final raw = store.getString(_configKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final token = await ServerSecretStore.readEntry(_secretKey);
      if (token == null || token.isEmpty) {
        // The connection config exists but its token is gone from secure
        // storage. This happened whenever a Navidrome re-save rewrote the
        // whole secret map without the ABS entry — it must never be silent
        // again, or the setup "gets deleted" with nothing to see.
        error = 'Saved Audiobookshelf token is missing — please reconnect.';
        notifyListeners();
        return;
      }
      connection = AudiobookshelfConnection(
          url: json['url'] as String, name: json['name'] as String);
      _api = AudiobookshelfApi(baseUrl: connection!.url, token: token);
      await refresh();
    } catch (_) {
      error = 'Saved Audiobookshelf connection could not be restored.';
      notifyListeners();
    }
  }

  Future<void> connect(
      {required String url, required String token, String? name}) async {
    final trimmed = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!Uri.tryParse(trimmed)!.hasScheme || token.trim().isEmpty) {
      error = 'Enter an http(s) server URL and an API token.';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    final api = AudiobookshelfApi(baseUrl: trimmed, token: token.trim());
    try {
      await api.validate();
      connection = AudiobookshelfConnection(
          name: (name?.trim().isNotEmpty ?? false)
              ? name!.trim()
              : 'Audiobookshelf',
          url: trimmed);
      _api = api;
      // writeEntry preserves every other secret (Navidrome passwords)
      // instead of rewriting the whole map from this feature's view.
      await ServerSecretStore.writeEntry(_secretKey, token.trim());
      final store = await AppPersistence.load();
      await store.setString(_configKey,
          jsonEncode({'name': connection!.name, 'url': connection!.url}));
      await refresh();
    } on AudiobookshelfApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not reach Audiobookshelf. Check the server URL.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Human-readable progress, e.g. "Fetching Podcasts (2 of 3)…" — a big
  /// library on a NAS takes real seconds, and a silent wait read as "the
  /// whole implementation is broken".
  String? progress;

  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    loading = true;
    error = null;
    progress = null;
    notifyListeners();
    try {
      final next = await api.libraries();
      libraries = next;
      // Sequential with per-library isolation: one slow or failing library
      // must neither time out the burst nor erase the libraries that did
      // fetch. Failures surface per library instead of as one dead screen.
      final entries = <MapEntry<String, List<SpokenItem>>>[];
      for (var i = 0; i < next.length; i++) {
        final library = next[i];
        progress = 'Fetching ${library.name} (${i + 1} of ${next.length})…';
        notifyListeners();
        try {
          entries.add(MapEntry(library.id, await api.items(library)));
        } on AudiobookshelfApiException catch (e) {
          entries.add(MapEntry(library.id, const <SpokenItem>[]));
          error = '${library.name}: ${e.message}';
        } catch (_) {
          entries.add(MapEntry(library.id, const <SpokenItem>[]));
          error = '${library.name}: could not reach the server.';
        }
      }
      itemsByLibrary
        ..clear()
        ..addEntries(entries);
    } on AudiobookshelfApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Audiobookshelf could not refresh right now.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
