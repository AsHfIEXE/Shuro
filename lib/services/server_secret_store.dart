import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// OS-backed storage for server passwords (implementation plan §7):
/// Android Keystore-encrypted preferences (Keychain on iOS). One JSON entry
/// maps server id -> password. Everything non-secret about a server (name,
/// URL, username) stays in SharedPreferences.
///
/// Read failures degrade to "no passwords known" — the app then asks for the
/// password again instead of crashing. That is the honest failure mode for a
/// device whose Keystore is broken (some emulators).
class ServerSecretStore {
  ServerSecretStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'shuro_server_passwords_v1';

  /// All stored passwords, keyed by server id. Never throws.
  static Future<Map<String, String>> readAll() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  /// Replaces the whole password map with [passwords] (servers that are gone
  /// lose their stored secret automatically). Never throws.
  static Future<void> writeAll(Map<String, String> passwords) async {
    try {
      if (passwords.isEmpty) {
        await _storage.delete(key: _key);
        return;
      }
      await _storage.write(key: _key, value: jsonEncode(passwords));
    } catch (_) {
      // Secure storage unavailable on this device — credentials fall back to
      // being asked again on next connect.
    }
  }

  /// Removes every stored password (Settings → Reset app data).
  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
