import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_card.dart';
import '../../widgets/artist_card.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';
import '../playlist/playlist_detail_screen.dart';

import '../../widgets/page_transitions.dart';
/// "03. Search" — field, recent searches, and grouped results across
/// Songs / Artists / Albums / Playlists.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    context.read<AppState>().addRecentSearch(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();

    final hasServer = appState.hasServer;
    final localResults = appState.localSongs.where((s) => s.title.toLowerCase().contains(_query.toLowerCase())).toList();
    final songResults = [if (hasServer) ...appState.searchCatalogSongs(_query), ...localResults];
    final artistResults = hasServer ? appState.searchCatalogArtists(_query) : const <Artist>[];
    final albumResults = hasServer ? appState.searchCatalogAlbums(_query) : const <Album>[];
    final playlistResults =
        appState.playlists.where((p) => p.name.toLowerCase().contains(_query.toLowerCase())).toList();
    final hasResults = songResults.isNotEmpty || artistResults.isNotEmpty || albumResults.isNotEmpty || playlistResults.isNotEmpty;

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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: kCardColor, borderRadius: BorderRadius.circular(23)),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: kMutedTextColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: false,
                        onChanged: (v) => setState(() => _query = v),
                        onSubmitted: _submit,
                        style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search songs, artists, albums...',
                          hintStyle: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() {
                          _controller.clear();
                          _query = '';
                        }),
                        child: const Icon(Icons.close_rounded, color: kMutedTextColor, size: 18),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _query.isEmpty
                  ? _RecentSearches(
                      terms: appState.recentSearches,
                      onTapTerm: (term) {
                        _controller.text = term;
                        setState(() => _query = term);
                      },
                      onClear: () => context.read<AppState>().clearRecentSearches(),
                    )
                  : !hasResults
                      ? EmptyStateView(icon: Icons.search_off_rounded, title: 'No results for "$_query"',
                          subtitle: 'Try a different search term.')
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            if (songResults.isNotEmpty) ...[
                              SectionHeader(title: 'Songs', padding: const EdgeInsets.fromLTRB(20, 12, 20, 4)),
                              for (final song in songResults.take(6))
                                SongTile(
                                  song: song,
                                  onTap: () {
                                    _submit(_query);
                                    player.playSong(song, queue: songResults);
                                  },
                                ),
                            ],
                            if (artistResults.isNotEmpty) ...[
                              SectionHeader(title: 'Artists', padding: const EdgeInsets.fromLTRB(20, 16, 20, 4)),
                              SizedBox(
                                height: 132,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  itemCount: artistResults.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                                  itemBuilder: (context, i) {
                                    final artist = artistResults[i];
                                    return SizedBox(
                                      width: 100,
                                      child: ArtistCard(
                                        artist: artist,
                                        onTap: () {
                                          _submit(_query);
                                          pushDrillDownOnce(context, ArtistDetailScreen(artist: artist));
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            if (albumResults.isNotEmpty) ...[
                              SectionHeader(title: 'Albums', padding: const EdgeInsets.fromLTRB(20, 16, 20, 4)),
                              SizedBox(
                                height: 190,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  itemCount: albumResults.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                                  itemBuilder: (context, i) {
                                    final album = albumResults[i];
                                    return SizedBox(
                                      width: 140,
                                      child: AlbumCard(
                                        album: album,
                                        onTap: () {
                                          _submit(_query);
                                          pushDrillDownOnce(context, AlbumDetailScreen(album: album));
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            if (playlistResults.isNotEmpty) ...[
                              SectionHeader(title: 'Playlists', padding: const EdgeInsets.fromLTRB(20, 16, 20, 4)),
                              for (final playlist in playlistResults)
                                PlaylistCard(
                                  playlist: playlist,
                                  onTap: () {
                                    _submit(_query);
                                    pushDrillDownOnce(context, PlaylistDetailScreen(playlist: playlist));
                                  },
                                ),
                            ],
                          ],
                        ),
            ),
          ],
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
              Text('Recent searches', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              GestureDetector(
                onTap: onClear,
                child: Text('Clear', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final term in terms)
                GestureDetector(
                  onTap: () => onTapTerm(term),
                  child: Chip(
                    label: Text(term, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 12)),
                    backgroundColor: kCardColor,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    side: BorderSide.none,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
