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
      final token = (await ServerSecretStore.readAll())[_secretKey];
      if (token == null || token.isEmpty) return;
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
      final secrets = await ServerSecretStore.readAll();
      secrets[_secretKey] = token.trim();
      await ServerSecretStore.writeAll(secrets);
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

  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final next = await api.libraries();
      libraries = next;
      final entries = await Future.wait(next.map(
          (library) async => MapEntry(library.id, await api.items(library))));
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
