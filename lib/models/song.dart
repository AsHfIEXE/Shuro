import 'package:flutter/material.dart';
import 'audio_info.dart';

/// A single track. [gradientColors] drives the per-artist theming used for
/// the progress ring, play button glow, and artwork placeholders.
/// [localFilePath] is set for songs imported from the device instead of a
/// Navidrome server — null for everything from the server library.
class Song {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String albumId;
  final Duration duration;
  final List<Color> gradientColors;
  final ImageProvider? artwork;
  final AudioInfo audioInfo;
  final String? localFilePath;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.albumId,
    required this.duration,
    required this.gradientColors,
    this.artwork,
    this.audioInfo = const AudioInfo(),
    this.localFilePath,
  });

  bool get isLocal => localFilePath != null;
}

/// Extra now-playing metadata a backend/[AppState] knows that [Song] alone
/// doesn't carry — the real album title, a URL the lock-screen/notification
/// can load art from. Resolved via `PlayerController.metadataResolver`
/// (wired in app.dart to `AppState.nowPlayingMetadataFor`) so
/// [PlayerController] still never needs to import AppState or a repository
/// — it only knows the plain shape of what comes back.
class NowPlayingMetadata {
  final String? albumTitle;
  final Uri? artUri;
  const NowPlayingMetadata({this.albumTitle, this.artUri});
}
