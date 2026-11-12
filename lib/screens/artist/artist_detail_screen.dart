import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../backend/subsonic_api.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/build_from_mode.dart';
import '../../models/song.dart';
import '../../services/artist_artwork_service.dart';
import '../../services/multi_server.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/artist_actions_sheet.dart';
import '../../widgets/album_year_card.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/cache_helpers.dart';
import '../../widgets/click_region.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';

typedef _SimilarArtist = ({String id, String name, String? imageUrl});

enum _DiscoFilter { all, albums, singles, appearsOn }

/// "06. Artists > Artist detail" — per the Artist detail board: a hero with
/// the circular portrait, "ARTIST" eyebrow, real counts (albums · songs ·
/// length · cached) and Play / Shuffle / Cache all / Similar mix, then POPULAR
/// (with "Show all N" and play counts) beside ABOUT + SIMILAR ARTISTS
/// (getArtistInfo2), then DISCOGRAPHY with All / Albums / Singles and EPs /
/// Appears on chips.
class ArtistDetailScreen extends StatefulWidget {
  final Artist artist;
  const ArtistDetailScreen({super.key, required this.artist});

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  String? _bio;
  List<_SimilarArtist> _similar = const [];
  bool _showAll = false;
  _DiscoFilter _filter = _DiscoFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInfo());
  }

  Future<void> _loadInfo() async {
    if (!mounted) return;
    final api = context.read<ServerSession>().apiForId(widget.artist.id);
    if (api == null || widget.artist.id.isEmpty) return;
    final info = await api.artistInfoWithSimilar(MultiServerLibrary.remoteIdOf(widget.artist.id));
    if (!mounted) return;
    setState(() {
      _bio = _cleanBio(info.biography);
      _similar = info.similar;
    });
  }

  /// Last.fm biographies carry an HTML "Read more" anchor; strip tags.
  static String? _cleanBio(String? raw) {
    if (raw == null) return null;
    final text = raw
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
    return text.isEmpty ? null : text;
  }

  void _openSimilar(_SimilarArtist s) {
    final appState = context.read<AppState>();
    Artist? found;
    for (final a in appState.catalogArtists) {
      if (a.id == s.id || MultiServerLibrary.remoteIdOf(a.id) == s.id) {
        found = a;
        break;
      }
    }
    found ??= appState.catalogArtists
        .where((a) => a.name.toLowerCase() == s.name.toLowerCase())
        .firstOrNull;
    if (found == null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('${s.name} isn\'t in your library')));
      return;
    }
    Navigator.of(context).push(drillDownRoute(ArtistDetailScreen(artist: found)));
  }

  void _similarMix(AppState appState, PlayerController player, List<Song> songs) {
    if (songs.isEmpty) return;
    final top = appState.songsByIds(widget.artist.topSongIds);
    final seed = top.isNotEmpty ? top.first : songs.first;
    final queue = ShuroPulse.buildFrom(seed, BuildFromMode.similar, appState, targetLength: 25);
    player.playSong(seed, queue: queue.isEmpty ? songs : queue);
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('Similar mix from ${widget.artist.name}')));
  }

  List<Album> _discography(AppState appState, List<Album> own, _DiscoFilter f) {
    bool isSingle(Album a) {
      if (a.releaseTypes.contains('single') || a.releaseTypes.contains('ep')) return true;
      return a.releaseTypes.isEmpty && a.songIds.isNotEmpty && a.songIds.length <= 3;
    }

    List<Album> out;
    switch (f) {
      case _DiscoFilter.all:
        out = own;
      case _DiscoFilter.albums:
        out = own.where((a) => !isSingle(a)).toList();
      case _DiscoFilter.singles:
        out = own.where(isSingle).toList();
      case _DiscoFilter.appearsOn:
        final ids = {for (final a in own) a.id};
        final appearing = <String>{
          for (final s in appState.catalogSongs)
            if (s.artistId == widget.artist.id && !ids.contains(s.albumId)) s.albumId,
        };
        out = appState.catalogAlbums.where((a) => appearing.contains(a.id)).toList();
    }
    return [...out]..sort((a, b) => b.year.compareTo(a.year));
  }

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final artworkService = context.watch<ArtistArtworkService>();
    final topSongs = appState.songsByIds(artist.topSongIds);
    final albums = appState.albumsForArtist(artist.id);
    final artistSongs = appState.catalogSongs.where((s) => s.artistId == artist.id).toList();
    final isFav = appState.isFavoriteArtist(artist.id);
    final totalDuration = artistSongs.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
    final cachedCount = offlineSongIds(appState, artistSongs).length;

    final resolvedArt = artist.artwork ?? artworkService.forArtist(id: artist.id, name: artist.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.read<ArtistArtworkService>().warmUp([(id: artist.id, name: artist.name)]);
    });

    final playlist = topSongs.isNotEmpty ? topSongs : artistSongs;
    final disco = _discography(appState, albums, _filter);

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: DesktopContentFrame(
          maxWidth: DesktopTokens.contentStandard,
          child: topSongs.isEmpty && albums.isEmpty && artistSongs.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: _BackCircleButton(onPressed: () => Navigator.of(context).maybePop()),
                    ),
                    const Expanded(
                      child: EmptyStateView(
                        icon: Icons.album_rounded,
                        title: 'No albums found',
                        subtitle: "There's nothing from this artist in the connected library right now.",
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _BackCircleButton(onPressed: () => Navigator.of(context).maybePop()),
                      ),
                    ),
                    Entrance(
                      child: _ArtistHeader(
                        artist: artist,
                        artwork: resolvedArt,
                        songCount: artistSongs.length,
                        albumCount: albums.length,
                        totalDuration: totalDuration,
                        cachedCount: cachedCount,
                        isFav: isFav,
                        hasSongs: playlist.isNotEmpty,
                        onPlay: () => player.playSong(playlist.first, queue: playlist),
                        onShuffle: () {
                          final queue = [...playlist]..shuffle();
                          player.playSong(queue.first, queue: queue);
                        },
                        onCacheAll: () => cacheSongsWithFeedback(context, appState, artistSongs, artist.name),
                        onSimilar: () => _similarMix(appState, player, artistSongs),
                        onFavorite: () => appState.toggleFavoriteArtist(artist.id),
                        onMore: () => showArtistActionsSheet(context, artist),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(builder: (context, c) {
                      final wide = c.maxWidth >= 800;
                      final popular = _PopularCard(
                        songs: topSongs,
                        total: artistSongs.length,
                        showAll: _showAll,
                        onToggleAll: () => setState(() => _showAll = !_showAll),
                        onPlay: (song, queue) => player.playSong(song, queue: queue),
                      );
                      final about = _AboutCard(bio: _bio, similar: _similar, onSimilar: _openSimilar);
                      if (topSongs.isEmpty && _bio == null && _similar.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 7, child: popular),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 3, child: about),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [popular, const SizedBox(height: 16), about],
                              ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
                      child: Text('DISCOGRAPHY', style: _eyebrow),
                    ),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final (i, f) in _DiscoFilter.values.indexed)
                            Padding(
                              padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
                              child: _Chip(
                                label: switch (f) {
                                  _DiscoFilter.all => 'All',
                                  _DiscoFilter.albums => 'Albums',
                                  _DiscoFilter.singles => 'Singles and EPs',
                                  _DiscoFilter.appearsOn => 'Appears on',
                                },
                                active: _filter == f,
                                onTap: () => setState(() => _filter = f),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (disco.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Text('Nothing here yet.',
                            style: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 13)),
                      )
                    else
                      SizedBox(
                        height: 232,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: disco.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (context, i) => Entrance(
                            delay: Entrance.stagger(i),
                            enabled: i < 12,
                            child: AlbumYearCard(
                              album: disco[i],
                              onTap: () => Navigator.of(context)
                                  .push(drillDownRoute(AlbumDetailScreen(album: disco[i]))),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

TextStyle get _eyebrow => GoogleFonts.getFont(currentFontFamily,
    color: kMuted2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2);

/// 2200000 -> "2.2M", 982000 -> "982K".
String _compactCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
  return '$n';
}

/// Board back affordance: a 36 px circle on white 7%.
class _BackCircleButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _BackCircleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: kGlass, shape: BoxShape.circle),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: kTextColor, size: 16),
        ),
      ),
    );
  }
}

/// h44 action pill — violet filled for Play, glass for the rest.
class _ActionPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool glass;

  const _ActionPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = kTextColor;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: glass
                ? kSurfaceColor.withValues(alpha: 0.25)
                : (onTap != null ? kBrandColor : kBrandColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(999),
            border: glass ? Border.all(color: Colors.white.withValues(alpha: 0.5)) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: foreground, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 40/44 px circular icon action for the wash header (white 10% disc).
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final size = isDesktopPlatform ? 40.0 : 44.0;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: color ?? kTextColor),
        ),
      ),
    );
  }
}

String _formatTrackDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// The artist hero: colour wash + mesh blobs + circular portrait, "ARTIST"
/// eyebrow, name, the stats line and the action pills. Wide windows lay the
/// portrait beside the text; narrow ones centre the pair.
class _ArtistHeader extends StatelessWidget {
  final Artist artist;
  final ImageProvider? artwork;
  final int songCount;
  final int albumCount;
  final Duration totalDuration;
  final int cachedCount;
  final bool isFav;
  final bool hasSongs;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onCacheAll;
  final VoidCallback onSimilar;
  final VoidCallback onFavorite;
  final VoidCallback onMore;

  const _ArtistHeader({
    required this.artist,
    required this.artwork,
    required this.songCount,
    required this.albumCount,
    required this.totalDuration,
    required this.cachedCount,
    required this.isFav,
    required this.hasSongs,
    required this.onPlay,
    required this.onShuffle,
    required this.onCacheAll,
    required this.onSimilar,
    required this.onFavorite,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final meta = [
      '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
      '$songCount ${songCount == 1 ? 'song' : 'songs'}',
      if (totalDuration.inMinutes > 0) hoursMinutes(totalDuration),
      '$cachedCount cached',
    ].join(' · ');

    Widget actions({bool centered = false}) => Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ActionPill(label: 'Play', icon: Icons.play_arrow_rounded, onTap: hasSongs ? onPlay : null),
            _ActionPill(label: 'Shuffle', icon: Icons.shuffle_rounded, onTap: hasSongs ? onShuffle : null, glass: true),
            _ActionPill(label: 'Cache all', icon: Icons.download_rounded, onTap: hasSongs ? onCacheAll : null, glass: true),
            _ActionPill(label: 'Similar mix', onTap: hasSongs ? onSimilar : null, glass: true),
            _CircleAction(
              icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
              color: isFav ? kPinkLight : null,
              onTap: onFavorite,
            ),
            _CircleAction(icon: Icons.more_vert_rounded, tooltip: 'More options', onTap: onMore),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final portrait = wide ? 160.0 : 120.0;
        final nameStyle = wide
            ? headingFont(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1)
            : headingFont(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5);
        final eyebrow = GoogleFonts.getFont(currentFontFamily,
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.68);
        final metaStyle =
            GoogleFonts.getFont(currentFontFamily, color: Colors.white.withValues(alpha: 0.92), fontSize: 13);

        Widget portraitWidget() => Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: kSurfaceColor,
                border: Border.fromBorderSide(BorderSide(color: Colors.white24)),
              ),
              child: ArtworkThumb(
                gradientColors: artist.gradientColors,
                artwork: artwork,
                size: portrait,
                radius: 999,
                icon: Icons.person_rounded,
                iconSize: portrait * 0.35,
              ),
            );

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(artist.gradientColors.first, kSurfaceColor, 0.25)!,
                Color.lerp(artist.gradientColors.last, kSurfaceColor, 0.55)!,
              ],
            ),
            borderRadius: BorderRadius.circular(wide ? 22 : 16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              const Positioned.fill(child: MeshBlobs(opacity: 0.16)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: const [0, 0.75],
                      colors: [
                        kSurfaceColor.withValues(alpha: 0.62),
                        kSurfaceColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              if (wide)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      portraitWidget(),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ARTIST', style: eyebrow),
                            const SizedBox(height: 4),
                            Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                            const SizedBox(height: 4),
                            Text(meta, style: metaStyle),
                            const SizedBox(height: 16),
                            actions(),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      portraitWidget(),
                      const SizedBox(height: 12),
                      Text('ARTIST', style: eyebrow),
                      const SizedBox(height: 2),
                      Text(artist.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: nameStyle),
                      const SizedBox(height: 4),
                      Text(meta, textAlign: TextAlign.center, style: metaStyle),
                      const SizedBox(height: 12),
                      actions(centered: true),
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

/// POPULAR: top songs (first five, "Show all N" expands to every song the
/// server listed) with play counts when reported.
class _PopularCard extends StatelessWidget {
  final List<Song> songs;
  final int total;
  final bool showAll;
  final VoidCallback onToggleAll;
  final void Function(Song song, List<Song> queue) onPlay;

  const _PopularCard({
    required this.songs,
    required this.total,
    required this.showAll,
    required this.onToggleAll,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();
    final shown = showAll ? songs : songs.take(5).toList();
    final canToggle = songs.length > 5;
    final allCount = songs.length > total ? songs.length : total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('POPULAR', style: _eyebrow)),
            if (canToggle)
              ClickRegion(
                onTap: onToggleAll,
                child: Text(showAll ? 'Show less' : 'Show all $allCount',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kVioletLight, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kRaisedColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kHairline),
          ),
          child: Column(
            children: [
              for (final (i, song) in shown.indexed)
                Entrance(
                  delay: Entrance.stagger(i),
                  enabled: i < 12,
                  child: _TopSongRow(song: song, index: i, onTap: () => onPlay(song, songs)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ABOUT + SIMILAR ARTISTS card.
class _AboutCard extends StatelessWidget {
  final String? bio;
  final List<_SimilarArtist> similar;
  final void Function(_SimilarArtist) onSimilar;

  const _AboutCard({required this.bio, required this.similar, required this.onSimilar});

  @override
  Widget build(BuildContext context) {
    if (bio == null && similar.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bio != null) ...[
            Text('ABOUT', style: _eyebrow),
            const SizedBox(height: 10),
            Text(bio!,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(currentFontFamily, color: kNavText, fontSize: 13, height: 1.5)),
          ],
          if (bio != null && similar.isNotEmpty) const SizedBox(height: 24),
          if (similar.isNotEmpty) ...[
            Text('SIMILAR ARTISTS', style: _eyebrow),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in similar.take(3))
                  Expanded(
                    child: ClickRegion(
                      onTap: () => onSimilar(s),
                      child: Column(
                        children: [
                          _SimilarAvatar(artist: s),
                          const SizedBox(height: 8),
                          Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kTextColor, fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SimilarAvatar extends StatelessWidget {
  final _SimilarArtist artist;
  const _SimilarAvatar({required this.artist});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    Artist? local;
    for (final a in appState.catalogArtists) {
      if (a.id == artist.id || MultiServerLibrary.remoteIdOf(a.id) == artist.id) {
        local = a;
        break;
      }
    }
    final image = artist.imageUrl != null ? NetworkImage(artist.imageUrl!) : local?.artwork;
    return ArtworkThumb(
      gradientColors: local?.gradientColors ?? const [kBrandColor, kVioletLight],
      artwork: image,
      size: 56,
      radius: 999,
      icon: Icons.person_rounded,
      iconSize: 24,
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClickRegion(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: ShuroMotion.std,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? kBrandColor : kGlass,
          borderRadius: BorderRadius.circular(999),
          border: active ? null : Border.all(color: kHairline),
        ),
        child: Text(label,
            style: GoogleFonts.getFont(currentFontFamily,
                color: active ? Colors.white : kNavText, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// One numbered Popular row: # · cover · title/album · play count · time · ⋮.
class _TopSongRow extends StatelessWidget {
  final Song song;
  final int index;
  final VoidCallback onTap;

  const _TopSongRow({required this.song, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    final albumTitle = context.read<AppState>().albumById(song.albumId)?.title;
    final playing = context.select<PlayerController, String?>((p) => p.currentSong?.id) == song.id;
    final titleColor = playing ? kVioletPale : kTextColor;

    return ContextMenuRegion(
      items: songContextMenuItems(context, song),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white.withValues(alpha: 0.045),
        onLongPress: isDesktopPlatform ? null : () => showSongActionsSheet(context, song),
        child: Container(
          height: desktop ? 52.0 : 56.0,
          decoration: BoxDecoration(
            color: playing ? kBrandColor.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Center(
                  child: playing
                      ? const PlayingBars(size: 14)
                      : Text('${index + 1}',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText, fontSize: 13)),
                ),
              ),
              ArtworkThumb(
                gradientColors: song.gradientColors,
                artwork: song.artwork,
                size: desktop ? 36.0 : 44.0,
                radius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: titleColor, fontSize: 14, fontWeight: FontWeight.w600)),
                    if (albumTitle != null)
                      Text(albumTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily, color: kStatusText, fontSize: 12)),
                  ],
                ),
              ),
              if (song.playCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(_compactCount(song.playCount),
                      style: GoogleFonts.getFont(currentFontFamily, color: kStatusText, fontSize: 13)),
                ),
              SizedBox(
                width: 52,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(_formatTrackDuration(song.duration),
                      style: GoogleFonts.getFont(currentFontFamily, color: kStatusText, fontSize: 13)),
                ),
              ),
              SizedBox(
                width: 40,
                child: Builder(
                  builder: (buttonContext) => InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      if (isDesktopPlatform) {
                        showSongMenuAtAnchor(context, song, buttonContext);
                      } else {
                        showSongActionsSheet(context, song);
                      }
                    },
                    child: Icon(Icons.more_horiz_rounded,
                        size: 18, color: playing ? kVioletLight : kMuted2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
