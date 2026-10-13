/// How album/song/playlist artwork is shaped across the app (Settings →
/// Appearance → Artwork style). Artist portraits stay circular, and the
/// Now Playing ring is part of that screen's fixed design.
enum ArtworkStyle {
  rounded('Rounded'),
  square('Square'),
  circle('Circle');

  final String label;
  const ArtworkStyle(this.label);
}
