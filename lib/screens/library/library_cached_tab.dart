import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/song.dart';
import '../../services/audio_cache.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/click_region.dart';
import '../../widgets/motion.dart';
import '../../widgets/state_views.dart';
import 'library_controls.dart';

/// A cached file paired with the library song it belongs to.
class CachedSong {
  final Song song;
  final AudioCacheEntry entry;
  const CachedSong(this.song, this.entry);
}

/// Songs in the streaming cache that still resolve to a library song,
/// newest-cached first (one row per song, even when several qualities exist).
List<CachedSong> cachedSongsOf(AppState appState) {
  final byKey = <String, Song>{
    for (final s in appState.allSongs) AudioCache.sanitizeId(s.id): s,
  };
  final seen = <String>{};
  final out = <CachedSong>[];
  for (final e in AudioCache.instance.entries()) {
    final song = byKey[e.songKey];
    if (song == null || !seen.add(e.songKey)) continue;
    out.add(CachedSong(song, e));
  }
  return out;
}

enum _CachedSort { recent, titleAz, artistAz, size }

const _cachedSortLabels = <_CachedSort, String>{
  _CachedSort.recent: 'Recently cached',
  _CachedSort.titleAz: 'Title A to Z',
  _CachedSort.artistAz: 'Artist A to Z',
  _CachedSort.size: 'Largest first',
};

const int _cachedPage = 50;

String _limitLabel(int mb) => mb >= 1024
    ? '${(mb / 1024) % 1 == 0 ? (mb ~/ 1024) : (mb / 1024).toStringAsFixed(1)} GB'
    : '$mb MB';

/// Library > Cached (board "Library - Cached"): cache usage / available
/// offline / cache settings cards, then a table of the songs in the song
/// cache with filter, sort, Shuffle and Play all. Rows can be removed from
/// the cache individually.
class CachedTab extends StatefulWidget {
  const CachedTab({super.key});

  @override
  State<CachedTab> createState() => _CachedTabState();
}

class _CachedTabState extends State<CachedTab> {
  final TextEditingController _filter = TextEditingController();
  _CachedSort _sort = _CachedSort.recent;
  int _shown = _cachedPage;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  String _quality(CachedSong c) {
    final tag = c.entry.quality.toLowerCase();
    final info = c.song.audioInfo;
    if (tag == 'original' || tag == 'orig' || tag == 'raw') {
      if (info.hasFormat) {
        final parts = <String>[info.format!.toUpperCase()];
        if (info.hasBitDepth && info.hasSampleRate) {
          parts.add(
              '${info.bitDepth}/${(info.sampleRateHz! / 1000).round()}');
        } else if (info.hasBitrate) {
          parts.add('${info.bitrateKbps}');
        }
        return parts.join(' ');
      }
      return 'Original';
    }
    if (int.tryParse(tag) != null) return '$tag kbps';
    return tag.isEmpty ? 'Unknown' : tag[0].toUpperCase() + tag.substring(1);
  }

  Future<void> _clear(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'Clear the song cache?',
      message:
          'Cached songs are deleted from this device and stream again when played. Downloads are not touched.',
      confirmLabel: 'Clear cache',
    );
    if (ok) await AudioCache.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    return ListenableBuilder(
      listenable: AudioCache.instance,
      builder: (context, _) {
        final all = cachedSongsOf(appState);
        final query = _filter.text.trim().toLowerCase();
        final filtered = query.isEmpty
            ? List<CachedSong>.of(all)
            : all
                .where((c) =>
                    c.song.title.toLowerCase().contains(query) ||
                    c.song.artist.toLowerCase().contains(query) ||
                    (appState.albumById(c.song.albumId)?.title ?? '')
                        .toLowerCase()
                        .contains(query))
                .toList();
        switch (_sort) {
          case _CachedSort.recent:
            // entries() already arrives newest first.
            break;
          case _CachedSort.titleAz:
            filtered.sort((a, b) =>
                a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase()));
          case _CachedSort.artistAz:
            filtered.sort((a, b) => a.song.artist
                .toLowerCase()
                .compareTo(b.song.artist.toLowerCase()));
          case _CachedSort.size:
            filtered.sort((a, b) => b.entry.bytes.compareTo(a.entry.bytes));
        }
        final queue = [for (final c in filtered) c.song];
        final shown = filtered.take(_shown).toList();
        final totalBytes = all.fold<int>(0, (n, c) => n + c.entry.bytes);

        return DesktopContentFrame(
          maxWidth: DesktopTokens.contentTable,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              _StatCards(
                cachedCount: all.length,
                cachedBytes: totalBytes,
                onClear: () => _clear(context),
              ),
              const SizedBox(height: 16),
              LibraryToolbar(
                padding: EdgeInsets.zero,
                countLabel: query.isEmpty
                    ? '${all.length} cached'
                    : '${filtered.length} of ${all.length} cached',
                filterController: _filter,
                filterHint: 'Filter cached songs',
                onFilterChanged: () => setState(() => _shown = _cachedPage),
                trailing: [
                  LibrarySortMenu<_CachedSort>(
                      value: _sort,
                      options: _cachedSortLabels,
                      onSelected: (s) => setState(() => _sort = s)),
                  LibraryPill(
                      label: 'Shuffle',
                      icon: Icons.shuffle_rounded,
                      glass: true,
                      onTap: queue.isEmpty
                          ? null
                          : () {
                              final s = [...queue]..shuffle();
                              player.playSong(s.first, queue: s);
                            }),
                  LibraryPill(
                      label: 'Play all',
                      icon: Icons.play_arrow_rounded,
                      onTap: queue.isEmpty
                          ? null
                          : () => player.playSong(queue.first, queue: queue)),
                ],
              ),
              const SizedBox(height: 16),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: EmptyStateView(
                    icon: Icons.cloud_done_rounded,
                    title: 'Nothing cached yet',
                    subtitle:
                        'Songs you stream are kept here automatically so they keep playing without a connection. Explicit downloads live under Downloads.',
                  ),
                )
              else if (filtered.isEmpty)
                EmptyStateView(
                  icon: Icons.search_off_rounded,
                  title: 'No cached songs match',
                  subtitle:
                      'Nothing matches "${_filter.text.trim()}" · clear the filter to see all ${all.length} cached songs.',
                )
              else
                _table(context, shown, queue, filtered.length, all.length),
            ],
          ),
        );
      },
    );
  }

  Widget _table(BuildContext context, List<CachedSong> shown, List<Song> queue,
      int filteredCount, int totalCount) {
    final appState = context.read<AppState>();
    final player = context.read<PlayerController>();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final columns = [
        const LibraryColumn('TITLE', flex: 4),
        if (wide) const LibraryColumn('ARTIST', flex: 3),
        if (wide) const LibraryColumn('ALBUM', flex: 3),
        if (wide) const LibraryColumn('QUALITY', width: 110),
        const LibraryColumn('SIZE', width: 80),
        if (wide) const LibraryColumn('STATUS', width: 130),
        const LibraryColumn('TIME', width: 56),
      ];
      return Container(
        decoration: libraryTableCardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            LibraryTableHeader(columns: columns),
            for (var i = 0; i < shown.length; i++)
              Entrance(
                key: ValueKey('cached-${shown[i].entry.songKey}'),
                delay: Entrance.stagger(i),
                child: _row(context, shown[i], i, columns, wide, queue,
                    appState, player),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: LibraryFooter(
                      shown: shown.length,
                      total: filteredCount,
                      noun: 'cached songs',
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onLoadMore: shown.length < filteredCount
                          ? () => setState(() => _shown += _cachedPage)
                          : null,
                    ),
                  ),
                  if (wide)
                    Text('Cached songs keep playing without a connection',
                        style: libraryCellStyle(color: kStatusText, size: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _row(
      BuildContext context,
      CachedSong c,
      int i,
      List<LibraryColumn> columns,
      bool wide,
      List<Song> queue,
      AppState appState,
      PlayerController player) {
    final song = c.song;
    final album = appState.albumById(song.albumId)?.title ?? '—';
    return LibraryTableRow(
      columns: columns,
      onTap: () => player.playSong(song, queue: queue),
      index: Text('${i + 1}',
          style: libraryCellStyle(color: kStatusText, size: 13)),
      cells: [
        Row(
          children: [
            ArtworkThumb(
                gradientColors: song.gradientColors,
                artwork: song.artwork,
                size: 36,
                radius: 8),
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
                          color: kTextColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(libraryAgo(c.entry.modified),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: libraryCellStyle(color: kStatusText, size: 12)),
                ],
              ),
            ),
          ],
        ),
        if (wide)
          Text(song.artist,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: libraryCellStyle()),
        if (wide)
          Text(album,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: libraryCellStyle()),
        if (wide)
          Text(_quality(c),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: libraryCellStyle()),
        Text(libraryBytes(c.entry.bytes), style: libraryCellStyle()),
        if (wide) const _OfflineReadyBadge(),
        Text(libraryDuration(song.duration), style: libraryCellStyle()),
      ],
      trailing: IconButton(
        tooltip: 'Remove from cache',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.delete_outline_rounded,
            size: 18, color: kMuted2),
        onPressed: () => AudioCache.instance.remove(song.id),
      ),
    );
  }
}

class _OfflineReadyBadge extends StatelessWidget {
  const _OfflineReadyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kGreen.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 13, color: kGreenLight),
          const SizedBox(width: 4),
          Text('Offline ready',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kGreenLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Cache usage / available offline / cache settings, all driven by
/// [AudioCache].
class _StatCards extends StatelessWidget {
  final int cachedCount;
  final int cachedBytes;
  final VoidCallback onClear;
  const _StatCards(
      {required this.cachedCount,
      required this.cachedBytes,
      required this.onClear});

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(20),
        decoration: libraryTableCardDecoration(),
        child: child,
      );

  Widget _label(String t) => Text(t,
      style: GoogleFonts.getFont(currentFontFamily,
          color: kStatusText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0));

  @override
  Widget build(BuildContext context) {
    final cache = AudioCache.instance;
    final used = cache.usedBytes;
    final limit = cache.limitBytes;
    final fraction = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);

    final usage = _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _label('CACHE USAGE'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: kBrandColor.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999)),
            child: Text('${(fraction * 100).round()}% full',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kVioletPale,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(libraryBytes(used),
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kTextColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text('of ${_limitLabel(cache.limitMb)} limit',
                style: libraryCellStyle(color: kStatusText, size: 14)),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(children: [
            Container(height: 8, color: Colors.white.withValues(alpha: 0.08)),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 280),
              curve: ShuroMotion.std,
              widthFactor: fraction,
              child: Container(
                  height: 8,
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [kBrandColor, kVioletLight]))),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Free ${libraryBytes((limit - used).clamp(0, limit))}',
            style: libraryCellStyle(color: kStatusText, size: 12)),
      ],
    ));

    final offline = _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('AVAILABLE OFFLINE'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$cachedCount',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kTextColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text(cachedCount == 1 ? 'song' : 'songs',
                style: libraryCellStyle(color: kStatusText, size: 14)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
            cachedCount == 0
                ? 'Songs you stream are cached automatically'
                : '${libraryBytes(cachedBytes)} saved on this device',
            style: libraryCellStyle(color: kStatusText, size: 12)),
      ],
    ));

    final settings = _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('CACHE SETTINGS'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: Text('Cache while streaming',
                  style: libraryCellStyle(color: kTextColor, size: 14))),
          Switch(
            value: cache.enabled,
            activeThumbColor: Colors.white,
            activeTrackColor: kBrandColor,
            onChanged: cache.setEnabled,
          ),
        ]),
        Row(children: [
          Expanded(
              child: Text('Limit',
                  style: libraryCellStyle(color: kTextColor, size: 14))),
          PopupMenuButton<int>(
            color: kCardColor,
            initialValue: cache.limitMb,
            onSelected: cache.setLimitMb,
            position: PopupMenuPosition.under,
            itemBuilder: (context) => [
              for (final mb in AudioCache.limitChoicesMb)
                PopupMenuItem<int>(
                    value: mb,
                    child: Text(_limitLabel(mb),
                        style: libraryCellStyle(color: Colors.white))),
            ],
            child: Container(
              height: 30,
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_limitLabel(cache.limitMb),
                    style: libraryCellStyle(color: kTextColor)),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 14, color: kMuted2),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ClickRegion(
          onTap: cachedCount == 0 ? null : onClear,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delete_outline_rounded,
                size: 15,
                color: cachedCount == 0 ? kMuted3 : const Color(0xFFFF6B6B)),
            const SizedBox(width: 6),
            Text('Clear cache',
                style: libraryCellStyle(
                    color:
                        cachedCount == 0 ? kMuted3 : const Color(0xFFFF6B6B),
                    size: 13)),
          ]),
        ),
      ],
    ));

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        // A stretched Row in a ListView has unbounded height: without
        // IntrinsicHeight this threw and blanked everything under it.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: usage),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: offline),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: settings),
            ],
          ),
        );
      }
      return Column(children: [
        usage,
        const SizedBox(height: 12),
        offline,
        const SizedBox(height: 12),
        settings,
      ]);
    });
  }
}
