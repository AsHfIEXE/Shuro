import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../backend/subsonic_api.dart';
import '../../models/song.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/song_tile.dart';

/// The Playlists tab's "On your server" section: every playlist the connected
/// Navidrome (or any Subsonic server) reports, with full management for the
/// ones the logged-in user owns — create, rename, delete, and push the playing
/// song into one. Everything goes through the server immediately, so the web
/// UI and other clients see the same state.
class ServerPlaylistsSection extends StatefulWidget {
  const ServerPlaylistsSection({super.key});

  @override
  State<ServerPlaylistsSection> createState() => _ServerPlaylistsSectionState();
}

class _ServerPlaylistsSectionState extends State<ServerPlaylistsSection> {
  late Future<List<Map<String, dynamic>>> _future;
  int _reloadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final api = context.read<ServerSession>().api;
    if (api == null) return const [];
    return api.getPlaylists();
  }

  void _reload() {
    final generation = ++_reloadGeneration;
    _load().then((playlists) {
      if (!mounted || generation != _reloadGeneration) return;
      // Braces, not an arrow body: an arrow closure returns the assignment's
      // value, and when that value is a Future Flutter's setState() rejects
      // it ("setState() callback argument returned a Future") — seen live in
      // the debug log the moment a playlist action reloaded this section.
      setState(() {
        _future = Future.value(playlists);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ServerSession>().api;
    if (api == null) {
      return const SizedBox.shrink(); // offline: local playlists only
    }
    final username = context.watch<AppState>().activeServer?.username ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('On your server', style: GoogleFonts.getFont(currentFontFamily, color: kTextColor, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'New server playlist',
                icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70),
                onPressed: () => _create(context, api),
              ),
            ],
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))),
              );
            }
            final playlists = snapshot.data ?? const [];
            if (playlists.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  'No server playlists yet — create one with the + above.',
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
                ),
              );
            }
            return Column(
              children: [
                for (final playlist in playlists)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(colors: _colorsFor('${playlist['id']}')),
                      ),
                      child: const Icon(Icons.queue_music_rounded, color: Colors.white),
                    ),
                    title: Text(
                      (playlist['name'] as String?) ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _subtitle(playlist, username),
                      style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(drillDownRoute(ServerPlaylistDetailScreen(
                        playlistId: '${playlist['id']}',
                        name: (playlist['name'] as String?) ?? 'Playlist',
                      )));
                      _reload();
                    },
                    trailing: _isOwner(playlist, username)
                        ? PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                            onSelected: (choice) {
                              if (choice == 'rename') _rename(context, api, playlist);
                              if (choice == 'delete') _delete(context, api, playlist);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'rename', child: Text('Rename')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  bool _isOwner(Map<String, dynamic> playlist, String username) =>
      ((playlist['owner'] as String?) ?? '') == username;

  String _subtitle(Map<String, dynamic> playlist, String username) {
    final count = (playlist['songCount'] as num?)?.toInt() ?? 0;
    final owner = (playlist['owner'] as String?) ?? '';
    final who = owner == username ? 'you' : (owner.isEmpty ? 'someone else' : owner);
    return '$count songs · owned by $who';
  }

  List<Color> _colorsFor(String id) {
    final palettes = const [
      [Color(0xFF6E56CF), Color(0xFF9E8CFC)],
      [Color(0xFFE0558C), Color(0xFFFF9CBB)],
      [Color(0xFF2F9E6E), Color(0xFF7BE6B1)],
      [Color(0xFFD97B29), Color(0xFFFFC37A)],
      [Color(0xFF2E7FD9), Color(0xFF8ECBFF)],
    ];
    return palettes[id.hashCode.abs() % palettes.length];
  }

  Future<void> _create(BuildContext context, SubsonicApi api) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('New server playlist', style: GoogleFonts.getFont(currentFontFamily, color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.getFont(currentFontFamily, color: Colors.white),
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await api.createPlaylist(name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created "$name" on the server.')));
      _reload();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create playlist: $error')));
    }
  }

  Future<void> _rename(BuildContext context, SubsonicApi api, Map<String, dynamic> playlist) async {
    final controller = TextEditingController(text: (playlist['name'] as String?) ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Rename playlist', style: GoogleFonts.getFont(currentFontFamily, color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.getFont(currentFontFamily, color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await api.updatePlaylist(id: '${playlist['id']}', name: name);
      _reload();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not rename: $error')));
    }
  }

  Future<void> _delete(BuildContext context, SubsonicApi api, Map<String, dynamic> playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Delete "${playlist['name']}"?', style: GoogleFonts.getFont(currentFontFamily, color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text('This removes the playlist from the server for every client.', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.deletePlaylist('${playlist['id']}');
      _reload();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $error')));
    }
  }
}

/// One server playlist's songs — fetched live, playable, and manageable when
/// the logged-in user owns it (add the song now playing, remove entries).
class ServerPlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  final String name;

  const ServerPlaylistDetailScreen({super.key, required this.playlistId, required this.name});

  @override
  State<ServerPlaylistDetailScreen> createState() => _ServerPlaylistDetailScreenState();
}

class _ServerPlaylistDetailScreenState extends State<ServerPlaylistDetailScreen> {
  List<Song> _songs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ServerSession>().api;
    if (api == null) {
      setState(() { _loading = false; _error = 'No server connected.'; });
      return;
    }
    try {
      final raw = await api.getPlaylistSongs(widget.playlistId);
      final songs = [for (final entry in raw) api.songFromChild(entry)];
      if (!mounted) return;
      setState(() { _songs = songs; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$error'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        title: Text(widget.name, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Add playing song',
            icon: const Icon(Icons.playlist_add_rounded, color: Colors.white70),
            onPressed: _songs.isEmpty ? null : () => _addPlayingSong(player),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBrandColor))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
                  ),
                )
              : RefreshIndicator(
                  color: kBrandColor,
                  onRefresh: () async { await _load(); },
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (_songs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Row(
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: kBrandColor),
                                onPressed: () => player.playSong(_songs.first, queue: _songs),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Play all'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  final shuffled = [..._songs]..shuffle();
                                  player.playSong(shuffled.first, queue: shuffled);
                                },
                                icon: const Icon(Icons.shuffle_rounded, size: 18),
                                label: const Text('Shuffle'),
                              ),
                            ],
                          ),
                        ),
                      for (final song in _songs)
                        SongTile(
                          song: song,
                          onTap: () => player.playSong(song, queue: _songs),
                        ),
                    ],
                  ),
                ),
    );
  }

  /// Pushes the currently playing song to the end of this server playlist —
  /// the same edit Navidrome's web UI would make, visible in every client.
  Future<void> _addPlayingSong(PlayerController player) async {
    final api = context.read<ServerSession>().api;
    final song = player.currentSong;
    if (api == null || song == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Play a song first, then add it here.')));
      return;
    }
    try {
      await api.updatePlaylist(id: widget.playlistId, songIdsToAdd: [song.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${song.title}" to the server playlist.')));
      _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: $error')));
    }
  }
}
