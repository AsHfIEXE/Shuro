import 'package:shared_preferences/shared_preferences.dart';

/// Thin, typed wrapper around [SharedPreferences] — the one place the app
/// talks to on-device key-value storage. Deliberately generic (get/set by
/// key, not "saveServers()"/"loadFavorites()") so the actual shape of what's
/// persisted — JSON encoding, which fields matter — stays in [AppState]
/// next to the state it belongs to, instead of being duplicated here.
///
/// This is plain, unencrypted local storage: fine for settings, favorites,
/// and listening history, but it means a saved server's password sits on
/// disk in plain text the same way the rest of this app's state does.
/// Upgrading the server-credentials path specifically to
/// `flutter_secure_storage` is a reasonable follow-up, not something this
/// class pretends isn't true.
class AppPersistence {
  AppPersistence._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppPersistence> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPersistence._(prefs);
  }

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  bool? getBool(String key) => _prefs.getBool(key);

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  int? getInt(String key) => _prefs.getInt(key);

  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  List<String> getStringList(String key) => _prefs.getStringList(key) ?? const [];

  Future<void> setStringList(String key, List<String> value) => _prefs.setStringList(key, value);

  Future<void> remove(String key) => _prefs.remove(key);
}
