part of 'settings_screen.dart';

/// Settings -> Playback: how tracks start, transition and end.
///
/// Wired today: crossfade, ReplayGain on/off (PlaybackPrefs -> player via
/// app.dart), speed, skip silence, resume/remember queue, autoplay (queue end
/// "Autoplay"). Stored until the player reads them: gapless switch, fade on
/// pause/resume, ReplayGain album mode, untagged pre-amp, scrobble plays and
/// the "Repeat" queue-end choice.
extension _PlaybackPage on _SettingsScreenState {
  List<Widget> playbackSection(
      BuildContext context, AppState appState, PlaybackPrefs prefs) {
    final rgValue = !prefs.replayGain ? 'off' : prefs.replayGainMode;
    return [
      _SectionLabel('PLAYBACK',
          key: _sectionKey('playback'),
          highlighted: _highlighted == 'playback',
          subtitle:
              'How tracks start, transition and end. Sound shaping lives in Audio and EQ.'),
      _SettingsGroupCard(
        title: 'TRANSITIONS',
        rows: [
          _sliderRow(
            label: 'Crossfade',
            description: 'Blend the end of one track into the next.',
            value: prefs.crossfadeSeconds.toDouble(),
            min: 0,
            max: 12,
            divisions: 12,
            format: (v) => '${v.round()} s',
            onCommit: (v) => prefs.setCrossfadeSeconds(v.round()),
          ),
          _switchRow(
            label: 'Gapless playback',
            description: 'Skip the silence between tracks on the same album.',
            value: appState.gaplessPlayback,
            onChanged: (v) =>
                appState.toggleSetting(() => appState.gaplessPlayback = v),
          ),
          _switchRow(
            label: 'Fade on pause and resume',
            description: 'A short fade so stopping never clicks.',
            value: prefs.fadeOnPause,
            onChanged: prefs.setFadeOnPause,
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'LEVELING',
        rows: [
          _segmentedRow(
            label: 'ReplayGain',
            description: 'Match loudness between tracks and albums.',
            options: const [
              ('off', 'Off'),
              ('track', 'Track'),
              ('album', 'Album'),
            ],
            value: rgValue,
            onChanged: prefs.setReplayGainMode,
          ),
          _sliderRow(
            label: 'Pre-amp for untagged tracks',
            description: 'Used when a file has no ReplayGain tags.',
            value: prefs.untaggedPreampDb,
            min: -12,
            max: 12,
            divisions: 48,
            format: (v) => _formatDb(v).replaceAll('.0 dB', ' dB'),
            onCommit: prefs.setUntaggedPreampDb,
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'BEHAVIOUR',
        rows: [
          _switchRow(
            label: 'Resume where you left off',
            description: 'Restore the queue and position when Shuro opens.',
            value: appState.resumePlayback && appState.rememberQueue,
            onChanged: (v) => appState.toggleSetting(() {
              appState.resumePlayback = v;
              appState.rememberQueue = v;
            }),
          ),
          _switchRow(
            label: 'Scrobble plays',
            description: 'Report finished tracks to your server.',
            value: appState.scrobblePlays,
            onChanged: appState.updateScrobblePlays,
          ),
          _segmentedRow(
            label: 'When the queue ends',
            description: 'What happens after the last track.',
            options: const [
              ('stop', 'Stop'),
              ('repeat', 'Repeat'),
              ('similar', 'Autoplay'),
            ],
            value: appState.queueEnd,
            onChanged: appState.updateQueueEnd,
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'SPEED AND SILENCE',
        rows: [
          _NavRow(
            icon: Icons.speed_rounded,
            label: 'Playback speed',
            value: '${prefs.playbackSpeed.toStringAsFixed(2)}×',
            onTap: () => _pickPlaybackSpeed(context, prefs),
          ),
          _switchRow(
            label: 'Skip silence',
            description: 'Trim long quiet stretches inside tracks.',
            value: prefs.skipSilence,
            onChanged: prefs.setSkipSilence,
          ),
        ],
      ),
    ];
  }
}
