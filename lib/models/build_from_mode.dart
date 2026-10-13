/// The radiating options offered from a song/artist's "Build from this"
/// sheet — each is a different rule for expanding one seed into a queue.
enum BuildFromMode {
  similar,
  sameEra,
  deeperCuts,
  surpriseMe,
  smoothContinuation,
}

extension BuildFromModeInfo on BuildFromMode {
  String get label => switch (this) {
        BuildFromMode.similar => 'More like this',
        BuildFromMode.sameEra => 'Same era',
        BuildFromMode.deeperCuts => 'Deeper cuts',
        BuildFromMode.surpriseMe => 'Surprise me',
        BuildFromMode.smoothContinuation => 'Smooth continuation',
      };

  String get description => switch (this) {
        BuildFromMode.similar => 'Tracks that sound and feel like this one',
        BuildFromMode.sameEra => 'Stay around the same release period',
        BuildFromMode.deeperCuts => 'Less obvious picks from the same world',
        BuildFromMode.surpriseMe => 'A wider, more adventurous mix from this seed',
        BuildFromMode.smoothContinuation => 'An easy, low-contrast way to keep listening',
      };
}
