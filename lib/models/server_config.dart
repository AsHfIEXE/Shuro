/// [localOnly] means the user explicitly skipped connecting a server —
/// AuthGate treats it the same as [connected] for the purpose of entering
/// the main app, but AppState.hasServer is false, so every screen that
/// reads from a server's catalog shows local files only instead of the
/// mock Navidrome data.
enum ConnectionStatus { disconnected, connecting, connected, invalidCredentials, unreachable, localOnly }

/// A saved Navidrome server. [name] is what the user picks it by in the
/// server switcher — defaults to "Server N" (per connection order) when
/// left blank, so switching servers is never showing a bare URL.
class ServerConfig {
  final String id;
  final String name;
  final String url;
  final String username;
  final String password;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
  });

  ServerConfig copyWith({String? name, String? url, String? username, String? password}) => ServerConfig(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
      );
}
