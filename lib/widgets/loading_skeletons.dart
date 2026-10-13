import 'package:flutter/material.dart';

import 'shimmer_box.dart';

/// Skeleton screens for every loading state, so a fetch in flight reads as
/// "content is coming" instead of "this screen is empty / the app is stuck".
/// All of them are arrangements of [ShimmerBox] matching the shape of the
/// content they stand in for, and all of them stop animating the moment the
/// real content replaces them (and honour Reduce animations via ShimmerBox).
///
/// Usage rule across the app: a tab shows its skeleton while
/// `connectionStatus == connecting` AND its list is still empty; once real
/// content arrives the skeleton is replaced outright (no crossfade needed —
/// the shapes match 1:1).

/// Album grid placeholder: square covers + two text lines, in the same
/// two-per-row-ish rhythm the real grid uses at any width ( GridView with the
/// same delegate constants as the album tab).
class AlbumGridSkeleton extends StatelessWidget {
  final int count;
  const AlbumGridSkeleton({super.key, this.count = 12});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisSpacing: 18,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: count,
      itemBuilder: (context, i) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: ShimmerBox(height: double.infinity, radius: 12)),
          const SizedBox(height: 10),
          ShimmerBox(height: 12, width: 70 + (i % 3) * 18),
          const SizedBox(height: 6),
          ShimmerBox(height: 10, width: 90 + (i % 4) * 12),
        ],
      ),
    );
  }
}

/// Artist grid placeholder: circle + name line.
class ArtistGridSkeleton extends StatelessWidget {
  final int count;
  const ArtistGridSkeleton({super.key, this.count = 12});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 18,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: count,
      itemBuilder: (context, i) => Column(
        children: [
          const Expanded(
            child: ShimmerBox(
              height: double.infinity,
              width: double.infinity,
              radius: 999,
            ),
          ),
          const SizedBox(height: 10),
          ShimmerBox(height: 11, width: 60 + (i % 4) * 16),
        ],
      ),
    );
  }
}

/// Song-list placeholder: square thumb + two staggered text lines per row.
class SongListSkeleton extends StatelessWidget {
  final int count;
  const SongListSkeleton({super.key, this.count = 10});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: count,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const ShimmerBox(width: 48, height: 48, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(height: 12, width: 120 + (i % 5) * 22),
                  const SizedBox(height: 8),
                  ShimmerBox(height: 10, width: 80 + (i % 3) * 26),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Genre tile placeholder: wide rounded block with a centred name bar.
class GenreGridSkeleton extends StatelessWidget {
  final int count;
  const GenreGridSkeleton({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.7,
      ),
      itemCount: count,
      itemBuilder: (context, i) => Stack(
        alignment: Alignment.center,
        children: [
          const ShimmerBox(height: double.infinity, width: double.infinity, radius: 14),
          ShimmerBox(height: 12, width: 70 + (i % 3) * 24, radius: 6),
        ],
      ),
    );
  }
}

/// Generic row skeleton for detail screens (album tracks, artist top songs,
/// server playlists) — [rows] of thumb + two lines.
class DetailListSkeleton extends StatelessWidget {
  final int rows;
  const DetailListSkeleton({super.key, this.rows = 8});

  @override
  Widget build(BuildContext context) {
    return SongListSkeleton(count: rows);
  }
}
