import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_card.dart';
import '../../widgets/artist_card.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/playlist_collage_art.dart';
import '../../widgets/shuro_icons.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';
import '../playlist/playlist_detail_screen.dart';

/// "03. Search" (search-favorites board) — the large glass query field,
/// filter chips with live counts, a TOP RESULT card when a strong match
/// exists, then grouped sections across Songs / Artists / Albums /
/// Playlists. Live filtering, recent searches and every existing route are
/// unchanged; this is the visual refresh of the same behavior.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchFilter { all, songs, albums, artists, playlists }

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  _SearchFilter _filter = _SearchFilter.all;
  bool _songsExpanded = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    context.read<AppState>().addRecentSearch(trimmed);
  }

  void _clearQuery() {
    _controller.clear();
    setState(() {
      _query = '';
      _songsExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final hPad = wide ? 24.0 : 20.0;

    final hasServer = appState.hasServer;
    final q = _query.trim().toLowerCase();
    final localResults = q.isEmpty
        ? const <Song>[]
        : appState.localSongs.where((s) => s.title.toLowerCase().contains(q)).toList();
    final songResults = [
      if (hasServer && q.isNotEmpty) ...appState.searchCatalogSongs(_query),
      ...localResults,
    ];
    final artistResults = hasServer && q.isNotEmpty ? appState.searchCatalogArtists(_query) : const <Artist>[];
    final albumResults = hasServer && q.isNotEmpty ? appState.searchCatalogAlbums(_query) : const <Album>[];
    final playlistResults = q.isEmpty
        ? <Playlist>[]
        : appState.playlists.where((p) => p.name.toLowerCase().contains(q)).toList();
    final hasResults = songResults.isNotEmpty ||
        artistResults.isNotEmpty ||
        albumResults.isNotEmpty ||
        playlistResults.isNotEmpty;

    // A chip only exists for a category that actually has hits — no dead
    // filters. If the active filter's category emptied out on a new query,
    // the effective view falls back to All.
    final visibleFilters = <_SearchFilter>[_SearchFilter.all];
    if (songResults.isNotEmpty) visibleFilters.add(_SearchFilter.songs);
    if (albumResults.isNotEmpty) visibleFilters.add(_SearchFilter.albums);
    if (artistResults.isNotEmpty) visibleFilters.add(_SearchFilter.artists);
    if (playlistResults.isNotEmpty) visibleFilters.add(_SearchFilter.playlists);
    final effectiveFilter = visibleFilters.contains(_filter) ? _filter : _SearchFilter.all;

    final topHit = q.isEmpty ? null : _resolveTopHit(q, songResults, albumResults, artistResults, playlistResults);
    final showTopHit = topHit != null &&
        (effectiveFilter == _SearchFilter.all || _typeOfFilter(topHit) == effectiveFilter);

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // When this screen is pushed as its own route (Home's search bar does
            // exactly that), it needs an explicit way back: it has no AppBar, so
            // the only exit used to be the system back gesture — unreachable on
            // desktop and web, leaving the screen a dead end.
            if (Navigator.of(context).canPop())
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
                  child: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 8),
              child: _QueryField(
                controller: _controller,
                focus: _focus,
                query: _query,
                wide: wide,
                onChanged: (v) => setState(() {
                  _query = v;
                  // A new query invalidates an expanded Songs section —
                  // collapse it back to the board's preview row count.
                  _songsExpanded = false;
                }),
                onSubmitted: _submit,
                onClear: _clearQuery,
              ),
            ),
            if (q.isNotEmpty && hasResults)
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 4),
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final (index, filter) in visibleFilters.indexed)
                        Padding(
                          padding: EdgeInsets.only(right: index == visibleFilters.length - 1 ? 0 : 8),
                          child: _FilterChip(
                            label: switch (filter) {
                              _SearchFilter.all => 'All',
                              _SearchFilter.songs => 'Songs',
                              _SearchFilter.albums => 'Albums',
                              _SearchFilter.artists => 'Artists',
                              _SearchFilter.playlists => 'Playlists',
                            },
                            count: switch (filter) {
                              _SearchFilter.all => null,
                              _SearchFilter.songs => songResults.length,
                              _SearchFilter.albums => albumResults.length,
                              _SearchFilter.artists => artistResults.length,
                              _SearchFilter.playlists => playlistResults.length,
                            },
                            active: effectiveFilter == filter,
                            onTap: () => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: q.isEmpty
                  ? _RecentSearches(
                      terms: appState.recentSearches,
                      onTapTerm: (term) {
                        _controller.text = term;
                        setState(() {
                          _query = term;
                          _songsExpanded = false;
                        });
                      },
                      onClear: () => context.read<AppState>().clearRecentSearches(),
                    )
                  : !hasResults
                      ? EmptyStateView(icon: Icons.search_off_rounded, title: 'No results for "$_query"',
                          subtitle: 'Try a different search term.')
                      : _SearchResults(
                          appState: appState,
                          player: player,
                          wide: wide,
                          hPad: hPad,
                          filter: effectiveFilter,
                          topHit: showTopHit ? topHit : null,
                          songResults: songResults,
                          albumResults: albumResults,
                          artistResults: artistResults,
                          playlistResults: playlistResults,
                          songsExpanded: _songsExpanded,
                          onToggleSongs: () =>
                              setState(() => _songsExpanded = !_songsExpanded),
                          onSearchCommitted: () => _submit(_query),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  static _SearchFilter _typeOfFilter(_TopHit hit) => switch (hit.type) {
        'Song' => _SearchFilter.songs,
        'Album' => _SearchFilter.albums,
        'Artist' => _SearchFilter.artists,
        _ => _SearchFilter.playlists,
      };

  /// The TOP RESULT pick: an exact title/name match wins (song > album >
  /// artist > playlist); otherwise the strongest song match leads.
  static _TopHit? _resolveTopHit(
    String q,
    List<Song> songs,
    List<Album> albums,
    List<Artist> artists,
    List<Playlist> playlists,
  ) {
    for (final s in songs) {
      if (s.title.toLowerCase() == q) return _TopHit(type: 'Song', song: s);
    }
    for (final a in albums) {
      if (a.title.toLowerCase() == q) return _TopHit(type: 'Album', album: a);
    }
    for (final a in artists) {
      if (a.name.toLowerCase() == q) return _TopHit(type: 'Artist', artist: a);
    }
    for (final p in playlists) {
      if (p.name.toLowerCase() == q) return _TopHit(type: 'Playlist', playlist: p);
    }
    return songs.isEmpty ? null : _TopHit(type: 'Song', song: songs.first);
  }
}

/// The board's query pill: 56 px glass field, violet-tinted icon, violet
/// border while focused, clear affordance (Esc on desktop keyboards).
class _QueryField extends StatelessWidget {
  const _QueryField({
    required this.controller,
    required this.focus,
    required this.query,
    required this.wide,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String query;
  final bool wide;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final active = focus.hasFocus || query.isNotEmpty;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClear},
      child: Container(
        height: 56,
        padding: const EdgeInsets.only(left: 20, right: 12),
        decoration: BoxDecoration(
          color: kRaisedColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: active ? kBrandColor.withValues(alpha: 0.7) : kHairline,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: kVioletLight, size: wide ? 24 : 20),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: GoogleFonts.getFont(currentFontFamily, color: kTextColor, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search your music',
                  hintStyle: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 16),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (query.isNotEmpty) ...[
              if (wide)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('Esc to clear',
                      style: GoogleFonts.getFont(currentFontFamily, color: kMuted3, fontSize: 12)),
                ),
              _ClearButton(onTap: onClear),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kGlass,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 28,
          height: 28,
          child: Icon(Icons.close_rounded, color: kNavText, size: 16),
        ),
      ),
    );
  }
}

/// Board chip: 32 px pill, active = violet fill, inactive = glass + hairline,
/// with a live result count.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? kBrandColor : kGlass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: active ? BorderSide.none : BorderSide(color: kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: active ? Colors.white : kNavText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: active ? kVioletPale : kMuted3, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything below the chips for a non-empty query: the TOP RESULT card,
/// then Songs / Albums / Artists / Playlists sections, staggered in.
/// The board's small uppercase section label, as a reusable const widget.
class _BoardLabel extends StatelessWidget {
  const _BoardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.getFont(currentFontFamily,
          color: kMuted2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
    );
  }
}

/// The board's right-aligned "Show all 12" link on the Songs header row —
/// 12/SemiBold violet; flips to "Show less" once the section is expanded.
class _ShowAllLink extends StatelessWidget {
  const _ShowAllLink({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: expanded ? 'Show fewer songs' : 'Show all $count songs',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            expanded ? 'Show less' : 'Show all $count',
            style: GoogleFonts.getFont(currentFontFamily,
                color: kVioletLight, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.appState,
    required this.player,
    required this.wide,
    required this.hPad,
    required this.filter,
    required this.topHit,
    required this.songResults,
    required this.albumResults,
    required this.artistResults,
    required this.playlistResults,
    required this.songsExpanded,
    required this.onToggleSongs,
    required this.onSearchCommitted,
  });

  final AppState appState;
  final PlayerController player;
  final bool wide;
  final double hPad;
  final _SearchFilter filter;
  final _TopHit? topHit;
  final List<Song> songResults;
  final List<Album> albumResults;
  final List<Artist> artistResults;
  final List<Playlist> playlistResults;
  final bool songsExpanded;
  final VoidCallback onToggleSongs;
  final VoidCallback onSearchCommitted;

  @override
  Widget build(BuildContext context) {
    var section = 0;
    final children = <Widget>[];

    final topCard = topHit == null
        ? null
        : _TopResultCard(
            appState: appState,
            player: player,
            hit: topHit!,
            songQueue: songResults,
            onSearchCommitted: onSearchCommitted,
          );

    if (topCard != null) {
      // Desktop board layout with songs to spare: TOP RESULT card beside a
      // Songs panel. Otherwise the card leads full-width.
      if (wide && filter == _SearchFilter.all && songResults.isNotEmpty) {
        children.add(Entrance(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 430, child: _BoardLabel('Top result')),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Row(
                        children: [
                          const Expanded(child: _BoardLabel('Songs')),
                          if (songResults.length > 5)
                            _ShowAllLink(
                              count: songResults.length,
                              expanded: songsExpanded,
                              onTap: onToggleSongs,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 430, child: topCard),
                    const SizedBox(width: 24),
                    Expanded(
                        child: _songsPanel(context,
                            count: songsExpanded ? songResults.length : 5,
                            card: true)),
                  ],
                ),
              ],
            ),
          ),
        ));
      } else {
        children.add(Entrance(
          child: Padding(padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 0), child: topCard),
        ));
      }
    }

    if (filter == _SearchFilter.all || filter == _SearchFilter.songs) {
      if (!(wide && filter == _SearchFilter.all && songResults.isNotEmpty) &&
          songResults.isNotEmpty) {
        children.add(_songsSection(context, Entrance.stagger(++section)));
      }
    }

    if (filter == _SearchFilter.all || filter == _SearchFilter.albums) {
      if (albumResults.isNotEmpty) {
        children.add(Entrance(
          delay: Entrance.stagger(++section),
          child: _albumSection(context),
        ));
      }
    }
    if (filter == _SearchFilter.all || filter == _SearchFilter.artists) {
      if (artistResults.isNotEmpty) {
        children.add(Entrance(
          delay: Entrance.stagger(++section),
          child: _artistSection(context),
        ));
      }
    }
    if (filter == _SearchFilter.all || filter == _SearchFilter.playlists) {
      if (playlistResults.isNotEmpty) {
        children.add(Entrance(
          delay: Entrance.stagger(++section),
          child: _playlistSection(context),
        ));
      }
    }

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: children);
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 8),
        child: _BoardLabel(text),
      );

  Widget _songsSection(BuildContext context, Duration delay) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 8),
            child: Row(
              children: [
                const Expanded(child: _BoardLabel('Songs')),
                if (songResults.length > 6)
                  _ShowAllLink(
                    count: songResults.length,
                    expanded: songsExpanded,
                    onTap: onToggleSongs,
                  ),
              ],
            ),
          ),
          _songsPanel(context,
              count: songsExpanded ? songResults.length : 6, card: wide),
        ],
      );

  Widget _songsPanel(BuildContext context, {required int count, required bool card}) {
    final rows = [
      for (final (i, song) in songResults.take(count).indexed)
        Entrance(
          delay: Entrance.stagger(i),
          child: SongTile(
            song: song,
            onTap: () {
              onSearchCommitted();
              player.playOrToggle(song, queue: songResults);
            },
          ),
        ),
    ];
    if (!card) return Column(children: rows);
    return Container(
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: Column(children: rows),
    );
  }

  Widget _albumSection(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'Albums'),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: hPad),
              itemCount: albumResults.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final album = albumResults[i];
                return SizedBox(
                  width: 140,
                  child: AlbumCard(
                    album: album,
                    onTap: () {
                      onSearchCommitted();
                      pushDrillDownOnce(context, AlbumDetailScreen(album: album));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );

  Widget _artistSection(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'Artists'),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: hPad),
              itemCount: artistResults.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final artist = artistResults[i];
                return SizedBox(
                  width: 100,
                  child: ArtistCard(
                    artist: artist,
                    onTap: () {
                      onSearchCommitted();
                      pushDrillDownOnce(context, ArtistDetailScreen(artist: artist));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );

  Widget _playlistSection(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'Playlists'),
          for (final playlist in playlistResults)
            PlaylistCard(
              playlist: playlist,
              onTap: () {
                onSearchCommitted();
                pushDrillDownOnce(context, PlaylistDetailScreen(playlist: playlist));
              },
            ),
        ],
      );
}

class _TopHit {
  const _TopHit({required this.type, this.song, this.album, this.artist, this.playlist});

  final String type;
  final Song? song;
  final Album? album;
  final Artist? artist;
  final Playlist? playlist;
}

/// The board's big "TOP RESULT" card: artwork, title, type chip, meta line
/// and Play / Open actions wired to the same playback and routes the lists
/// below use.
class _TopResultCard extends StatelessWidget {
  const _TopResultCard({
    required this.appState,
    required this.player,
    required this.hit,
    required this.songQueue,
    required this.onSearchCommitted,
  });

  final AppState appState;
  final PlayerController player;
  final _TopHit hit;
  final List<Song> songQueue;
  final VoidCallback onSearchCommitted;

  List<Color> get _gradient => switch (hit.type) {
        'Song' => hit.song!.gradientColors,
        'Album' => hit.album!.gradientColors,
        'Artist' => hit.artist!.gradientColors,
        _ => hit.playlist!.gradientColors,
      };

  ImageProvider? get _artwork => switch (hit.type) {
        'Song' => hit.song!.artwork,
        'Album' => hit.album!.artwork,
        'Artist' => hit.artist!.artwork,
        _ => hit.playlist!.artwork,
      };

  String get _title => switch (hit.type) {
        'Song' => hit.song!.title,
        'Album' => hit.album!.title,
        'Artist' => hit.artist!.name,
        _ => hit.playlist!.name,
      };

  String get _subtitle {
    switch (hit.type) {
      case 'Song':
        return hit.song!.artist;
      case 'Album':
        final album = hit.album!;
        final year = album.year > 0 ? ' · ${album.year}' : '';
        return '${album.artist}$year · ${album.songIds.length} songs';
      case 'Artist':
        return '${hit.artist!.albumIds.length} albums';
      default:
        final playlist = hit.playlist!;
        final count = playlist.smartPreset != null
            ? ShuroPulse.smartPlaylistSongs(playlist.smartPreset!, appState).length
            : playlist.songIds.length;
        return '$count songs';
    }
  }

  /// The queue a Play press starts — whole album / artist top songs /
  /// playlist, or the search results for a song.
  List<Song> _playQueue() {
    switch (hit.type) {
      case 'Song':
        return songQueue;
      case 'Album':
        return appState.songsForAlbum(hit.album!.id);
      case 'Artist':
        return appState.songsByIds(hit.artist!.topSongIds);
      default:
        final playlist = hit.playlist!;
        return playlist.smartPreset != null
            ? ShuroPulse.smartPlaylistSongs(playlist.smartPreset!, appState)
            : appState.songsByIds(playlist.songIds);
    }
  }

  void _play() {
    final queue = _playQueue();
    if (queue.isEmpty) return;
    onSearchCommitted();
    player.playSong(queue.first, queue: queue);
  }

  void _open(BuildContext context) {
    onSearchCommitted();
    switch (hit.type) {
      case 'Album':
        pushDrillDownOnce(context, AlbumDetailScreen(album: hit.album!));
      case 'Artist':
        pushDrillDownOnce(context, ArtistDetailScreen(artist: hit.artist!));
      case 'Playlist':
        pushDrillDownOnce(context, PlaylistDetailScreen(playlist: hit.playlist!));
      default:
        final album = appState.albumById(hit.song!.albumId);
        if (album != null) pushDrillDownOnce(context, AlbumDetailScreen(album: album));
    }
  }

  bool get _canOpen => switch (hit.type) {
        'Song' => appState.albumById(hit.song!.albumId) != null,
        _ => true,
      };

  String get _openLabel => switch (hit.type) {
        'Artist' => 'Open artist',
        'Playlist' => 'Open playlist',
        _ => 'Open album',
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final coverSize = wide ? 122.0 : 96.0;
    return HoverLift(
      radius: const BorderRadius.all(Radius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kRaisedColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cover(coverSize),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(_title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: headingFont(
                              color: kTextColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              height: 30 / 24)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: kBrandColor.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(hit.type,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kVioletPale, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 8),
                      Text(_subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily, color: kStatusText, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _ActionButton(
                  label: 'Play',
                  primary: true,
                  icon: ShuroIcon(ShuroGlyph.play, size: 14),
                  onTap: _play,
                ),
                const SizedBox(width: 8),
                if (_canOpen)
                  _ActionButton(
                    label: _openLabel,
                    primary: false,
                    onTap: () => _open(context),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(double size) {
    if (hit.type == 'Playlist') {
      return SizedBox(width: size, height: size, child: PlaylistCollageArt(playlist: hit.playlist!, radius: 16));
    }
    return ArtworkThumb(
      gradientColors: _gradient,
      artwork: _artwork,
      size: size,
      radius: hit.type == 'Artist' ? 999 : 16,
      icon: hit.type == 'Artist' ? Icons.person_rounded : Icons.album_rounded,
      iconSize: size / 3,
    );
  }
}

/// Board buttons: primary violet pill (Play), ghost pill with hairline.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.primary,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool primary;
  final VoidCallback onTap;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? kBrandColor : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: primary ? BorderSide.none : BorderSide(color: kGlass),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              Text(label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: primary ? Colors.white : kTextColor,
                      fontSize: 13,
                      fontWeight: primary ? FontWeight.w700 : FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  final List<String> terms;
  final ValueChanged<String> onTapTerm;
  final VoidCallback onClear;

  const _RecentSearches({required this.terms, required this.onTapTerm, required this.onClear});

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) {
      return const EmptyStateView(icon: Icons.history_rounded, title: 'No recent searches');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent searches',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              GestureDetector(
                onTap: onClear,
                child: Text('Clear',
                    style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final term in terms)
                Material(
                  color: kGlass,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: kHairline)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onTapTerm(term),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.history_rounded, size: 14, color: kMuted2),
                          const SizedBox(width: 6),
                          Text(term,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kTextColor, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
