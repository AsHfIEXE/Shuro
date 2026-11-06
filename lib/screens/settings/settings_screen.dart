import 'dart:io';

import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'library_health_screen.dart';
import '../../app_info.dart';
import '../../models/download_state.dart';
import '../../models/song.dart';
import '../../playback/event_log.dart';
import '../../backend/subsonic_api.dart';
import '../../services/server_secret_store.dart';
import '../../services/device_profile.dart';
import '../../services/listenbrainz_service.dart';
import '../../services/download_service.dart';
import '../../services/playback_prefs.dart';
import '../../state/app_state.dart';
import '../../state/appearance_settings.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/sheet_scroll.dart';
import 'equalizer_sheet.dart';
import '../../widgets/state_views.dart';
import 'artwork_style_sheet.dart';
import 'avatar_editor_screen.dart';
import 'font_picker_sheet.dart';
import 'manage_servers_screen.dart';
import 'quality_selector_sheet.dart';
import '../onboarding/consent_screen.dart' show LegalTexts, DeviceBasics;
import '../../playback/audio_capability.dart';
import '../../playback/audio_diagnostics.dart';
import '../../widgets/motion.dart' show Entrance;
import '../../widgets/page_transitions.dart';

/// "14. Settings" — Account / Playback / Downloads / Cache / Appearance /
/// Behavior / About, per the requested structure.

Future<void> showListenBrainzSheet(BuildContext context) async {
  final controller =
      TextEditingController(text: ListenBrainzService.instance.token ?? '');
  var validating = false;
  String? status;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: kCardColor,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ListenBrainz',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Paste your ListenBrainz user token from listenbrainz.org/settings/. Scrobbles are sent when a track finishes.',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                obscureText: true,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'User token',
                  hintStyle: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white24, fontSize: 13),
                  filled: true,
                  fillColor: kSurfaceColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: 8),
                Text(status ?? '',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: validating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white70))
                      : const Icon(Icons.check_rounded, size: 18),
                  label:
                      Text(validating ? 'Validating…' : 'Connect ListenBrainz'),
                  onPressed: validating
                      ? null
                      : () async {
                          setSheetState(() {
                            validating = true;
                            status = null;
                          });
                          final username = await ListenBrainzService.instance
                              .setToken(controller.text.trim());
                          setSheetState(() {
                            validating = false;
                            status = username != null
                                ? 'Connected as $username'
                                : 'Invalid token — check it and try again.';
                          });
                        },
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  await ListenBrainzService.instance.disconnect();
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
                child: Text('Disconnect',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.redAccent, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Jump-to targets. One key per section, created on first use so the index
  /// and the widgets can never disagree about ids.
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{};
  String? _highlighted;

  /// Clears the highlight after a jump. Held so it can be cancelled on dispose
  /// instead of firing setState against a dead element.
  Timer? _highlightTimer;

  GlobalKey _sectionKey(String id) =>
      _sectionKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'settings-$id'));

  /// Every section, with the words a user would actually type to find it.
  /// Shared with the desktop rail.
  static const List<({String id, String title, String keywords})> index = [
    (
      id: 'account',
      title: 'Account',
      keywords: 'sign in server user logout connect disconnect'
    ),
    (
      id: 'playback',
      title: 'Playback',
      keywords: 'crossfade fade gapless transition speed silence skip'
    ),
    (
      id: 'audio',
      title: 'Audio & EQ',
      keywords:
          'quality stream streaming bitrate replaygain gain equalizer eq dsp signal path output volume'
    ),
    (
      id: 'lyrics',
      title: 'Lyrics',
      keywords: 'lyrics offset sync font auto follow'
    ),
    (
      id: 'downloads',
      title: 'Downloads',
      keywords: 'download offline storage save'
    ),
    (id: 'cache', title: 'Cache', keywords: 'cache clear size storage free'),
    (
      id: 'appearance',
      title: 'Appearance',
      keywords: 'theme dark light font accent colour color background immersive'
    ),
    (
      id: 'behavior',
      title: 'Behaviour',
      keywords: 'behaviour behavior notifications headset resume pause'
    ),
    (
      id: 'server',
      title: 'Server',
      keywords: 'server url address navidrome connect'
    ),
    (
      id: 'reset',
      title: 'Reset',
      keywords: 'reset delete wipe data clear everything'
    ),
    (
      id: 'performance',
      title: 'Performance',
      keywords: 'performance overlay diagnostics fps jank'
    ),
    (
      id: 'listenbrainz',
      title: 'ListenBrainz',
      keywords: 'listenbrainz scrobble token submit queue'
    ),
    (
      id: 'about',
      title: 'About',
      keywords: 'about version licences licenses sources report'
    ),
  ];

  Future<void> _jumpToSection(String id) async {
    setState(() => _highlighted = id);
    // Desktop two-pane: switch the rail to the section (the page itself does
    // not scroll any more). Mobile keeps the scroll below.
    _desktopSection.value = id;
    final target = _sectionKeys[id]?.currentContext;
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlighted = null);
    });
  }

  /// Which section the desktop rail shows; also the target of a search jump.
  final ValueNotifier<String> _desktopSection =
      ValueNotifier<String>('account');

  Future<void> _openSettingsSearch(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => _SettingsSearchDialog(index: index),
    );
    if (picked != null && mounted) await _jumpToSection(picked);
  }

  @override
  void dispose() {
    _desktopSection.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // View preferences live in their own notifier (see AppearanceSettings):
    // the background style for Now Playing / Lyrics and the immersive toggle.
    final appearance = context.watch<AppearanceSettings>();
    // Real playback effects (fade between songs, ReplayGain, speed, skip
    // silence). Their own notifier: app.dart pushes changes into the player,
    // so editing them here changes actual audio rather than storing a value
    // nothing reads.
    final playbackPrefs = context.watch<PlaybackPrefs>();

    // The same section widgets feed both layouts: the desktop two-pane view
    // shows one section at a time, mobile keeps the single scroll.
    final allSections = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            if (Navigator.of(context).canPop()) ...[
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              'Settings',
              // Page title per the boards: DesktopTokens.pageTitle
              // (36/800, tight tracking) on wide windows; 22/700 on
              // phones where the rail is a scroll instead.
              style: MediaQuery.sizeOf(context).width >= 600
                  ? DesktopTokens.pageTitle(
                      GoogleFonts.getFont(currentFontFamily, color: kTextColor))
                  : headingFont(
                      color: kTextColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Find a setting',
              onPressed: () => _openSettingsSearch(context),
              icon: const Icon(Icons.search_rounded, color: kNavText),
            ),
          ],
        ),
      ),

      _SectionLabel('ACCOUNT',
          key: _sectionKey('account'),
          highlighted: _highlighted == 'account',
          subtitle: 'Your servers, sign-in and profile.'),
      _SettingsGroupCard(
        title: 'SERVER & SIGN-IN',
        rows: [
          _NavRow(
            icon: Icons.dns_rounded,
            label: 'Server',
            description: appState.hasServer
                ? 'Music streams from your Navidrome server.'
                : 'Local files only, or a server you add.',
            value: appState.activeServer?.name ??
                (appState.isLocalOnly ? 'Local files only' : '—'),
            onTap: () => Navigator.of(context)
                .push(drillDownRoute(const ManageServersScreen())),
          ),
          if (appState.hasServer)
            // No tap affordance: there's no separate "account" page to
            // open (the server connection *is* the account), so this is
            // honest info display rather than a dead button.
            _NavRow(
                icon: Icons.person_rounded,
                label: 'Account',
                value: appState.activeServer?.username ?? '—'),
          _NavRow(
            icon: Icons.photo_camera_rounded,
            label: 'Profile photo',
            value: appState.userAvatarBytes != null ? 'Set' : 'Default',
            onTap: () => Navigator.of(context)
                .push(drillDownRoute(const AvatarEditorScreen())),
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'SESSION',
        rows: [
          _NavRow(
            icon: Icons.logout_rounded,
            // A local-only user never actually signed into anything, so
            // the destructive action here is framed as leaving that mode
            // (back to the Welcome screen) rather than a mismatched
            // "sign out" that implies an account session that never
            // existed.
            label: appState.isLocalOnly ? 'Exit local-only mode' : 'Sign out',
            destructive: true,
            onTap: () =>
                _confirmSignOut(context, isLocalOnly: appState.isLocalOnly),
          ),
        ],
      ),

      _SectionLabel('PLAYBACK',
          key: _sectionKey('playback'),
          highlighted: _highlighted == 'playback',
          subtitle:
              'How tracks start, transition and end. Sound shaping lives in Audio & EQ.'),
      // Effects that change real audio, each reading PlaybackPrefs.
      //
      // Fade between songs is a real volume fade across the boundary.
      // Gapless playback deliberately has no switch: the whole queue is
      // handed to the engine as one playlist (see PlayerController
      // _jumpTo), so consecutive tracks run into each other with no load
      // gap by construction rather than by a setting.
      _SettingsGroupCard(
        title: 'TRANSITIONS & SPEED',
        rows: [
          _NavRow(
            icon: Icons.graphic_eq_rounded,
            label: 'Fade between songs',
            description: 'Blend the end of one track into the next.',
            value: playbackPrefs.crossfadeSeconds == 0
                ? 'Off'
                : '${playbackPrefs.crossfadeSeconds}s',
            onTap: () => _pickCrossfade(context, playbackPrefs),
          ),
          _NavRow(
            icon: Icons.speed_rounded,
            label: 'Playback speed',
            value: '${playbackPrefs.playbackSpeed.toStringAsFixed(2)}×',
            onTap: () => _pickPlaybackSpeed(context, playbackPrefs),
          ),
          _ToggleRow(
            label: 'Skip silence',
            description: 'Trim long quiet stretches inside tracks.',
            value: playbackPrefs.skipSilence,
            onChanged: (v) => playbackPrefs.setSkipSilence(v),
          ),
        ],
      ),

      _SectionLabel('AUDIO & EQ',
          key: _sectionKey('audio'),
          highlighted: _highlighted == 'audio',
          subtitle:
              'Shape what you hear, and see exactly what reaches your device.'),
      // SettingsAudio board: the live chain from file to output,
      // built only from what audio_diagnostics can actually prove.
      const _SignalPathCard(),
      _SettingsGroupCard(
        title: 'STREAMING FROM NAVIDROME',
        rows: [
          _NavRow(
            icon: Icons.wifi_rounded,
            label: 'Wi-Fi quality',
            description:
                'Original sends the file as stored. Lower caps use the server to transcode.',
            value: appState.wifiQuality.label,
            onTap: () async {
              final selected = await showQualitySelectorSheet(context,
                  title: 'Wi-Fi Streaming Quality',
                  current: appState.wifiQuality);
              if (selected != null) appState.updateWifiQuality(selected);
            },
          ),
          _NavRow(
            icon: Icons.signal_cellular_alt_rounded,
            label: 'Mobile data quality',
            description: 'A lower cap for cellular saves data.',
            value: appState.mobileQuality.label,
            onTap: () async {
              final selected = await showQualitySelectorSheet(context,
                  title: 'Mobile Data Streaming Quality',
                  current: appState.mobileQuality);
              if (selected != null) appState.updateMobileQuality(selected);
            },
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'LEVELLING & EQ',
        rows: [
          // This is Android's system DSP. Do not present a dead desktop
          // control as though libmpv had received an equalizer setting.
          if (defaultTargetPlatform == TargetPlatform.android)
            _NavRow(
              icon: Icons.equalizer_rounded,
              label: 'Equalizer',
              description:
                  "Android's system equalizer, applied before the mixer.",
              onTap: () => showEqualizerSheet(context),
            ),
          // Loudness normalisation from the server's own ReplayGain tags.
          _ToggleRow(
            label: 'Replay gain',
            description:
                'Match loudness between tracks and albums, using tags in the file.',
            value: playbackPrefs.replayGain,
            onChanged: (v) => playbackPrefs.setReplayGain(v),
          ),
        ],
      ),

      _SectionLabel('LYRICS',
          key: _sectionKey('lyrics'),
          highlighted: _highlighted == 'lyrics',
          subtitle: 'How the words follow the music.'),
      _SettingsGroupCard(
        title: 'SYNC',
        rows: [
          _ToggleRow(
              label: 'Auto-scroll',
              value: appState.lyricsAutoScroll,
              onChanged: appState.updateLyricsAutoScroll),
          _NavRow(
            icon: Icons.sync_rounded,
            label: 'Sync adjustment',
            value: appState.lyricsOffsetMs == 0
                ? 'On time'
                : '${appState.lyricsOffsetMs > 0 ? '+' : ''}${appState.lyricsOffsetMs} ms',
            onTap: () => _adjustLyricsSync(context, appState),
          ),
        ],
      ),

      _SectionLabel('DOWNLOADS',
          key: _sectionKey('downloads'),
          highlighted: _highlighted == 'downloads',
          subtitle: 'Offline copies: what quality, where they land, and when.'),
      _SettingsGroupCard(
        title: 'DOWNLOADS & OFFLINE',
        rows: [
          _NavRow(
            icon: Icons.download_rounded,
            label: 'Download quality',
            value: appState.downloadQuality.label,
            onTap: () async {
              final selected = await showQualitySelectorSheet(context,
                  title: 'Download Quality', current: appState.downloadQuality);
              if (selected != null) appState.updateDownloadQuality(selected);
            },
          ),
          _ToggleRow(
              label: 'Wi-Fi only',
              description: 'Save data by never downloading over cellular.',
              value: appState.downloadWifiOnly,
              onChanged: (v) =>
                  appState.toggleSetting(() => appState.downloadWifiOnly = v)),
          // Wired to the real download service: opens the system folder
          // picker, and the chosen folder becomes where downloads are saved.
          // "App storage" means the default documents dir (which survives
          // app updates).
          _NavRow(
            icon: Icons.folder_rounded,
            label: 'Storage location',
            value: context.watch<DownloadService>().customLocation == null
                ? 'App storage'
                : 'Custom folder',
            onTap: () => _pickDownloadLocation(context),
          ),
          _NavRow(
            icon: Icons.delete_outline_rounded,
            label: 'Clear downloads',
            description: 'Downloaded songs are removed from this device.',
            destructive: true,
            onTap: () => _confirmClear(
              context,
              title: 'Clear all downloads?',
              message:
                  "You'll need to download songs again to play them offline.",
              onConfirm: () async {
                final downloads = context.read<DownloadService>();
                for (final song in downloads.songs) {
                  await downloads.remove(song.id);
                }
              },
            ),
          ),
        ],
      ),

      _SectionLabel('CACHE',
          key: _sectionKey('cache'),
          highlighted: _highlighted == 'cache',
          subtitle: 'What is stored on this device, and how to free it.'),
      const _CacheSection(),

      _SettingsGroupCard(
        title: 'LIBRARY',
        rows: [
          _NavRow(
            icon: Icons.health_and_safety_outlined,
            label: 'Library health',
            description: 'Artwork, tags and duplicates, checked on device.',
            value: 'Open',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const LibraryHealthScreen()),
            ),
          ),
        ],
      ),
      _SectionLabel('APPEARANCE',
          key: _sectionKey('appearance'),
          highlighted: _highlighted == 'appearance',
          subtitle: 'The look of the app, and of Now Playing and Lyrics.'),
      _SettingsGroupCard(
        title: 'THEME & TYPE',
        rows: [
          // No tap affordance: Shuro is deliberately dark-only (part of
          // its brand identity, not an oversight), so there's no picker
          // to open — this states that rather than pretending to offer one.
          _NavRow(
              icon: Icons.dark_mode_rounded,
              label: 'Theme',
              description:
                  'Dark is the identity — there is no light mode to switch to.',
              value: 'Dark'),
          _NavRow(
              icon: Icons.text_fields_rounded,
              label: 'Font',
              value: appState.fontFamily,
              onTap: () => showFontPickerSheet(context)),
          _ToggleRow(
              label: 'Dynamic colors',
              description: 'Tint surfaces from the current artwork.',
              value: appState.dynamicColors,
              onChanged: (v) =>
                  appState.toggleSetting(() => appState.dynamicColors = v)),
          _NavRow(
            icon: Icons.grid_view_rounded,
            label: 'Artwork style',
            value: appState.artworkStyle.label,
            onTap: () async {
              final selected =
                  await showArtworkStyleSheet(context, appState.artworkStyle);
              if (selected != null) appState.updateArtworkStyle(selected);
            },
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'NOW PLAYING & LYRICS',
        rows: [
          // Two looks for Now Playing / Lyrics: the animated blurred artwork, or
          // a static gradient from the same artwork-extracted palette. The
          // static option is genuinely cheaper per frame, so it doubles as the
          // low-end-device choice.
          _NavRow(
            icon: Icons.blur_on_rounded,
            label: 'Now Playing background',
            value: appearance.backgroundStyleLabel,
            onTap: () => _pickBackgroundStyle(context, appearance),
          ),
          // User-tuned blur strength and idle motion — the backdrop is the
          // surface people stare at longest, so both are preferences, not
          // constants.
          _NavRow(
            icon: Icons.blur_linear_rounded,
            label: 'Background blur',
            value: appearance.backdropBlurLabel,
            onTap: () => _pickBackdropBlur(context, appearance),
          ),
          _NavRow(
            icon: Icons.animation_rounded,
            label: 'Background motion',
            value: appearance.backdropMotionLabel,
            onTap: () => _pickBackdropMotion(context, appearance),
          ),
          // Word-by-word karaoke or plain line-by-line highlighting — a real
          // preference, and line mode is the honest one when only line
          // timings exist.
          _NavRow(
            icon: Icons.lyrics_rounded,
            label: 'Lyrics highlight',
            value: appearance.lyricsHighlightLabel,
            onTap: () => _pickLyricsHighlight(context, appearance),
          ),
          // Hides the status/navigation bars on Now Playing and Lyrics only —
          // deliberately scoped, so the rest of the app keeps its bars.
          _ToggleRow(
            label: 'Immersive screens',
            value: appearance.immersiveScreens,
            onChanged: appearance.setImmersiveScreens,
          ),
          _ToggleRow(
              label: 'Reduce animations',
              description: 'Also respects the system reduce-motion setting.',
              value: appState.reduceAnimations,
              onChanged: appState.updateReduceAnimations),
        ],
      ),

      _SectionLabel('BEHAVIOR',
          key: _sectionKey('behavior'),
          highlighted: _highlighted == 'behavior',
          subtitle:
              'Small habits: what Shuro remembers, and what it keeps to itself.'),
      _SettingsGroupCard(
        title: 'BEHAVIOUR',
        rows: [
          _NavRow(
            icon: Icons.undo_rounded,
            label: 'Undo last edit',
            value: appState.undoStack.canUndo
                ? appState.undoStack.lastLabel
                : 'Nothing to undo',
            onTap: appState.undoStack.canUndo
                ? () async {
                    final label = await appState.undoStack.undo();
                    if (label != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Undone: $label')),
                      );
                    }
                  }
                : null,
          ),
          _ToggleRow(
            label: 'Private listening',
            value: appState.privateListening,
            onChanged: appState.setPrivateListening,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              'Session only. New listening history and Last.fm activity stay off; downloads and playback still work.',
              style: GoogleFonts.getFont(
                currentFontFamily,
                color: kStatusText,
                fontSize: 12,
                height: 16 / 12,
              ),
            ),
          ),
          _ToggleRow(
              label: 'Autoplay',
              value: appState.autoplay,
              onChanged: (v) =>
                  appState.toggleSetting(() => appState.autoplay = v)),
          _ToggleRow(
              label: 'Remember queue',
              value: appState.rememberQueue,
              onChanged: (v) =>
                  appState.toggleSetting(() => appState.rememberQueue = v)),
          _ToggleRow(
              label: 'Resume playback',
              value: appState.resumePlayback,
              onChanged: (v) =>
                  appState.toggleSetting(() => appState.resumePlayback = v)),
        ],
      ),

      _SectionLabel('SERVER',
          key: _sectionKey('server'),
          highlighted: _highlighted == 'server',
          subtitle: 'Housekeeping on the connected server.'),
      _SettingsGroupCard(
        title: 'MAINTENANCE',
        rows: [
          _NavRow(
            icon: Icons.sync_rounded,
            label: 'Rescan server library',
            description: 'Ask Navidrome to look for new files.',
            onTap: () => _rescanServer(context),
          ),
        ],
      ),

      _SectionLabel('RESET',
          key: _sectionKey('reset'),
          highlighted: _highlighted == 'reset',
          subtitle: 'The one door that erases everything local.'),
      _SettingsGroupCard(
        title: 'DANGER ZONE',
        rows: [
          _NavRow(
            icon: Icons.restart_alt_rounded,
            label: 'Reset app data',
            value: 'Erase everything',
            destructive: true,
            onTap: () => _confirmResetApp(context),
          ),
        ],
      ),
      const _Note(
        'Signs out, forgets servers, favorites, playlists, downloads and every setting, '
        'then closes the app. Nothing on your Navidrome server is touched.',
      ),

      _SectionLabel('PERFORMANCE',
          key: _sectionKey('performance'),
          highlighted: _highlighted == 'performance',
          subtitle: 'One preset that tunes rendering to this device.'),
      _SettingsGroupCard(
        title: 'RENDER PRESET',
        rows: const [_PerformanceTile()],
      ),

      _SectionLabel('LISTENBRAINZ',
          key: _sectionKey('listenbrainz'),
          highlighted: _highlighted == 'listenbrainz',
          subtitle: 'Scrobble finished plays to your ListenBrainz account.'),
      _SettingsGroupCard(
        title: 'LINK YOUR ACCOUNT',
        rows: [
          _NavRow(
            icon: Icons.graphic_eq_rounded,
            label: 'ListenBrainz',
            value: ListenBrainzService.instance.token == null
                ? 'Not linked'
                : 'Linked',
            onTap: () => showListenBrainzSheet(context),
          ),
        ],
      ),
      _SectionLabel('ABOUT',
          key: _sectionKey('about'),
          highlighted: _highlighted == 'about',
          subtitle: 'What this app is, what it owes, and who it talks to.'),
      const _AboutBlock(),
      _SettingsGroupCard(
        title: 'APP DETAILS',
        rows: [
          _NavRow(
              icon: Icons.info_outline_rounded,
              label: 'Version',
              value: kAppVersion),
          // Play Store reviewers and screen-reader users both get real
          // value here: the exact facts the consent screen discloses, in
          // plain sight.
          _NavRow(
            icon: Icons.phone_android_rounded,
            label: 'Device & app info',
            onTap: () => _showDeviceInfoSheet(context),
          ),
          _NavRow(
            icon: Icons.gavel_rounded,
            label: 'Terms & privacy',
            onTap: () => _showTermsSheet(context),
          ),
          _NavRow(
            icon: Icons.bug_report_rounded,
            label: 'Report a problem',
            onTap: () => _showReportSheet(context),
          ),
          // Flutter collects licence text for every package the app links
          // (pub packages plus engine components) into one OBS-compliant
          // page — this is the standard, complete way to satisfy the MIT/BSD
          // "reproduce the copyright notice" clauses.
          _NavRow(
            icon: Icons.source_rounded,
            label: 'Open source licenses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Shuro',
              applicationVersion: kAppVersion,
            ),
          ),
          // The web services Shuro talks to are not pub packages, so they
          // never show up in showLicensePage — they get their own page.
          _NavRow(
            icon: Icons.public_rounded,
            label: 'Services & data sources',
            onTap: () => _showServiceAttributions(context),
          ),
        ],
      ),
      const SizedBox(height: 32),
    ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      },
      child: Scaffold(
        backgroundColor: kSurfaceColor,
        body: SafeArea(
          bottom: false,
          // The body owns its scrolling: mobile gets one Column in a
          // scroll view; desktop gets the two-pane rail (no outer scroll,
          // which would hand the Row an unbounded height).
          child: _SettingsBody(allSections, selected: _desktopSection),
        ),
      ),
    );
  }

  /// Device & app basics — the exact facts the consent screen discloses,
  /// shown in plain sight in About. On-device only, nothing transmitted.
  /// "Report a problem" — exports the redacted event log (last 300
  /// playback/UI events) with the same device facts About already shows.
  /// Nothing leaves the device unless the user copies or shares it.
  Future<void> _showReportSheet(BuildContext context) async {
    final basics = await DeviceBasics.collect();
    if (!context.mounted) return;
    final report = PlaybackEventLog.instance.exportText(device: basics);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => ScrollSafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report a problem',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'The last ${PlaybackEventLog.kMaxEvents} playback events, redacted — no credentials, no URLs. Copy it and send it when a bug appears.',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                // Shorter log window on short (landscape) screens so the header
                // and buttons stay reachable; the whole sheet scrolls too.
                constraints: BoxConstraints(
                    maxHeight: (MediaQuery.sizeOf(sheetContext).height * 0.4)
                        .clamp(120.0, 420.0)
                        .toDouble()),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kSurfaceColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      report,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white70, fontSize: 11, height: 1.35),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy report'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: report));
                    if (sheetContext.mounted) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('Report copied')),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeviceInfoSheet(BuildContext context) async {
    final basics = await DeviceBasics.collect();
    final screen = DeviceBasics.screenParts(context);
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => ScrollSafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Device & app info',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final row in [...basics.entries, ...screen.entries])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(row.key,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kMutedTextColor, fontSize: 12.5)),
                      const SizedBox(width: 16),
                      // Long values (model, OS build, screen description) wrap
                      // instead of overflowing the row.
                      Flexible(
                        child: Text(row.value,
                            textAlign: TextAlign.right,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Terms & privacy sheet — the same texts as the first-launch consent,
  /// reachable any time from About.
  Future<void> _showTermsSheet(BuildContext context) async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => DefaultTabController(
        length: 2,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            child: Column(
              children: [
                const TabBar(
                  tabs: [Tab(text: 'Terms'), Tab(text: 'Privacy')],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _legalScroll(LegalTexts.terms),
                      _legalScroll(LegalTexts.privacy),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legalScroll(String body) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(body,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white70, fontSize: 13, height: 1.55)),
      );

  /// Full local wipe: preferences (servers, favorites, history, playlists,
  /// settings, queue), the cover-art disk cache and the library cache. The
  /// server itself is never touched. Then the app closes — the next launch
  /// lands on a fresh Welcome screen.
  Future<void> _confirmResetApp(BuildContext context) async {
    final player = context.read<PlayerController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset app data?',
            style: GoogleFonts.getFont(currentFontFamily,
                color: kTextColor, fontWeight: FontWeight.w600)),
        content: Text(
          'This erases everything stored on this device: servers, favorites, playlists, downloads, lyrics settings and preferences. '
          'Your music on the server is not touched.',
          style: GoogleFonts.getFont(currentFontFamily,
              color: kMutedTextColor, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Erase everything',
                style: TextStyle(
                    color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Stop playback FIRST: the audio service is a foreground service that
    // outlives the activity — closing the app while it plays left the music
    // running with no app attached (the reported reset bug).
    await player.stopForExit();

    // 1) Preferences: the whole store — one clear covers servers, favorites,
    //    history, playlists, settings, saved queue and the downloads registry.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    // 2) Disk caches: cover art + library snapshots. And the secure store:
    //    a reset forgets the passwords too.
    await ServerSecretStore.clear();
    try {
      final base = await getApplicationSupportDirectory();
      for (final name in ['image_cache', 'library_cache']) {
        final dir = Directory('${base.path}${Platform.pathSeparator}$name');
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    } catch (_) {}

    // 3) Restart. On Android the app closes — the next launch starts from the
    //    Welcome screen. On web (Chrome testing) a page can't close itself, so
    //    the data is cleared and the user reloads; the reload lands on the
    //    fresh Welcome screen too.
    if (kIsWeb) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: kCardColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('App data cleared',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kTextColor, fontWeight: FontWeight.w600)),
            content: Text(
              'Everything stored by Shuro was erased. Reload the page to start fresh.',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMutedTextColor, fontSize: 13.5, height: 1.45),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK',
                    style: TextStyle(
                        color: kBrandColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      }
      return;
    }
    await SystemNavigator.pop();
  }

  /// Picks how Now Playing and Lyrics paint their background.
  void _pickBackgroundStyle(
      BuildContext context, AppearanceSettings appearance) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Now Playing background',
                      style: headingFont(
                          color: kTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              for (final style in BackgroundStyle.values)
                ListTile(
                  leading: Icon(
                    style == appearance.backgroundStyle
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: style == appearance.backgroundStyle
                        ? kBrandColor
                        : kMutedTextColor,
                  ),
                  title: Text(
                    switch (style) {
                      BackgroundStyle.animatedBlur => 'Animated blur',
                      BackgroundStyle.animatedGradient => 'Animated gradient',
                      BackgroundStyle.staticArtwork => 'Static artwork colours',
                    },
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    switch (style) {
                      BackgroundStyle.animatedBlur =>
                        'The cover, blurred and drifting behind the artwork — like Apple Music',
                      BackgroundStyle.animatedGradient =>
                        'The cover\'s colours, slowly drifting — alive without any image processing',
                      BackgroundStyle.staticArtwork =>
                        'A still gradient from the cover\'s own colours — cheapest to render',
                    },
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12),
                  ),
                  onTap: () {
                    appearance.setBackgroundStyle(style);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Slider for the backdrop blur multiplier; changes apply live to the sheet's
  /// own preview text, and to any open Now Playing instantly via the provider.
  void _pickBackdropBlur(BuildContext context, AppearanceSettings appearance) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ScrollSafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final value = appearance.backdropBlurScale;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 18),
                  Text('Background blur',
                      style: headingFont(
                          color: kTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'How strongly the artwork is blurred behind Now Playing and Lyrics. Open Now Playing to see the change live.',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12),
                  ),
                  Slider(
                    value: value,
                    min: 0.4,
                    max: 2.0,
                    divisions: 8,
                    label: appearance.backdropBlurLabel,
                    activeColor: kBrandColor,
                    onChanged: (v) {
                      appearance.setBackdropBlurScale(v);
                      setSheetState(() {});
                    },
                  ),
                  Center(
                    child: Text(
                      appearance.backdropBlurLabel,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Three idle-motion levels for the backdrop.
  void _pickBackdropMotion(
      BuildContext context, AppearanceSettings appearance) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Background motion',
                      style: headingFont(
                          color: kTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              for (final motion in BackdropMotion.values)
                ListTile(
                  leading: Icon(
                    appearance.backdropMotion == motion
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: appearance.backdropMotion == motion
                        ? kBrandColor
                        : kMutedTextColor,
                  ),
                  title: Text(
                    switch (motion) {
                      BackdropMotion.still => 'Still',
                      BackdropMotion.subtle => 'Subtle',
                      BackdropMotion.normal => 'Normal (default)',
                      BackdropMotion.lively => 'Fast',
                    },
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    switch (motion) {
                      BackdropMotion.still =>
                        'The artwork holds completely still',
                      BackdropMotion.subtle =>
                        'Barely-there drift — slower and shallower than default',
                      BackdropMotion.normal =>
                        'The designed slow breathe (18-second cycle)',
                      BackdropMotion.lively =>
                        'Fast drifting colours — clearly visible motion',
                    },
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12),
                  ),
                  onTap: () {
                    appearance.setBackdropMotion(motion);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the lyrics fill word by word or highlight whole lines.
  void _pickLyricsHighlight(
      BuildContext context, AppearanceSettings appearance) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Lyrics highlight',
                      style: headingFont(
                          color: kTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              for (final mode in LyricsHighlight.values)
                ListTile(
                  leading: Icon(
                    appearance.lyricsHighlight == mode
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: appearance.lyricsHighlight == mode
                        ? kBrandColor
                        : kMutedTextColor,
                  ),
                  title: Text(
                    switch (mode) {
                      LyricsHighlight.word => 'Word by word',
                      LyricsHighlight.line => 'Line by line',
                    },
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    switch (mode) {
                      LyricsHighlight.word =>
                        'Each word lights up as it is sung — karaoke style',
                      LyricsHighlight.line =>
                        'The whole line lights up at once — no word fill',
                    },
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12),
                  ),
                  onTap: () {
                    appearance.setLyricsHighlight(mode);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Crossfade length picker (Off / 2 / 4 / 6 seconds).
  void _pickCrossfade(BuildContext context, PlaybackPrefs prefs) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Fade between songs',
                      style: headingFont(
                          color: kTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              for (final seconds in const [0, 2, 4, 6])
                ListTile(
                  leading: Icon(
                    prefs.crossfadeSeconds == seconds
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: prefs.crossfadeSeconds == seconds
                        ? kBrandColor
                        : kMutedTextColor,
                  ),
                  title: Text(
                    seconds == 0 ? 'Off' : '${seconds}s fade',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    seconds == 0
                        ? 'Songs switch at full volume'
                        : 'Each song fades out over its last ${seconds}s',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12),
                  ),
                  onTap: () {
                    prefs.setCrossfadeSeconds(seconds);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Playback speed picker.
  void _pickPlaybackSpeed(BuildContext context, PlaybackPrefs prefs) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Playback speed',
                      style: headingFont(
                          color: kTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              for (final speed in const [0.75, 1.0, 1.25, 1.5, 2.0])
                ListTile(
                  leading: Icon(
                    prefs.playbackSpeed == speed
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: prefs.playbackSpeed == speed
                        ? kBrandColor
                        : kMutedTextColor,
                  ),
                  title: Text(
                    '${speed.toStringAsFixed(2)}×',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  onTap: () {
                    prefs.setPlaybackSpeed(speed);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the system folder picker through the download service and reports
  /// the outcome. The chosen folder is persisted; cancelling changes nothing.
  Future<void> _pickDownloadLocation(BuildContext context) async {
    final downloads = context.read<DownloadService>();
    final path = await downloads.pickLocation();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(path == null
              ? 'No folder chosen — downloads stay in app storage.'
              : 'Downloads will be saved to: $path')),
    );
  }

  /// Asks the connected server to scan for new/changed files (startScan), and
  /// reports how many files it currently knows about. Fire-and-forget UX: the
  /// scan itself runs server-side; we just kick it off.
  void _rescanServer(BuildContext context) {
    final api = context.read<ServerSession>().api;
    if (api == null) {
      showSuccessSnackBar(context, 'Connect to a server first.');
      return;
    }
    showSuccessSnackBar(context, 'Asking the server to rescan…');
    api.startScan().then((status) {
      if (!context.mounted) return;
      showSuccessSnackBar(context,
          'Rescan started — the server knows ${status.count} files so far.');
    }).catchError((_) {
      if (context.mounted)
        showErrorSnackBar(context, 'Could not reach the server.');
    });
  }

  /// Chooses the karaoke fill renderer for the lyrics screen.
  /// What each remote service is used for. These are services, not code —
  /// they carry no licence obligations like pub packages do, but naming them
  /// is the honest thing to do and costs one page.
  static const List<({String name, String usage})> _serviceEntries = [
    (
      name: 'LRCLIB (lrclib.net)',
      usage:
          'Synced and unsynced lyrics, including word-level timing where contributors recorded it.'
    ),
    (
      name: 'Last.fm / Libre.fm',
      usage:
          'Optional scrobbling — reporting the tracks you play to the account you authorize yourself. Uses the AudioScrobbler protocol.'
    ),
    (
      name: 'MusicBrainz',
      usage:
          'Album and artist metadata enrichment, and cover-art lookups when your server has no artwork.'
    ),
    (
      name: 'Cover Art Archive',
      usage: 'Album artwork for releases identified through MusicBrainz.'
    ),
    (
      name: 'Navidrome / OpenSubsonic',
      usage:
          'Your own music server — the Subsonic API it speaks is what Shuro is built around.'
    ),
  ];

  void _showServiceAttributions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text('Services & data sources',
                style: headingFont(
                    color: kTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Shuro talks to your own Navidrome server, and to these open services for extras. Each is used only for the purpose listed, and only when you use the matching feature.',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMutedTextColor, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final entry in _serviceEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(entry.usage,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kMutedTextColor, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _adjustLyricsSync(BuildContext context, AppState appState) {
    // The edited value has to live outside the dialog's builder. Reading it
    // from AppState inside the builder (what this used to do) reset it on every
    // rebuild, so ±100 never accumulated, the label never changed, and "Done"
    // saved the value it had started with — the adjustment appeared to do
    // nothing at all.
    final offset = ValueNotifier<int>(appState.lyricsOffsetMs);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: kCardColor,
            title: Text('Sync adjustment',
                style: headingFont(
                    color: kTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  offset.value == 0
                      ? 'On time'
                      : '${offset.value > 0 ? '+' : ''}${offset.value} ms — lyrics appear ${offset.value > 0 ? 'sooner' : 'later'}',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kMutedTextColor, fontSize: 12),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          color: Colors.white70),
                      onPressed: () =>
                          setDialogState(() => offset.value -= 100),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text('${offset.value} ms',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          color: Colors.white70),
                      onPressed: () =>
                          setDialogState(() => offset.value += 100),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => setDialogState(() => offset.value = 0),
                  child: const Text('Reset')),
              TextButton(
                onPressed: () {
                  appState.updateLyricsOffset(offset.value);
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmSignOut(BuildContext context, {required bool isLocalOnly}) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text(isLocalOnly ? 'Exit local-only mode?' : 'Sign out?',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text(
          isLocalOnly
              ? "You'll go back to the start screen. Your imported local files stay on this device."
              : "You'll need to reconnect to your server to use the app again.",
          style: GoogleFonts.getFont(currentFontFamily,
              color: kMutedTextColor, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<AppState>().disconnect();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text(isLocalOnly ? 'Exit' : 'Sign out',
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context,
      {required String title,
      required String message,
      required VoidCallback onConfirm}) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text(title,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text(message,
            style: GoogleFonts.getFont(currentFontFamily,
                color: kMutedTextColor, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
              showSuccessSnackBar(context, 'Cleared');
            },
            child:
                const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

/// Shuro's identity, front and center in Settings rather than just a
/// splash-screen tagline — name, logo, positioning line, and what the app
/// actually is, so "what is this app" is answered without leaving Settings.
class _AboutBlock extends StatelessWidget {
  const _AboutBlock();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 40),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kAppName,
                      style: headingFont(
                          color: kTextColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  Text(kAppTagline,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMutedTextColor, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(kAppDescription,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMutedTextColor, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 10),
          Text(kAppTaglineAlt,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kTextColor.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool highlighted;

  /// One-line explainer under the heading (Settings board section headers).
  final String? subtitle;
  const _SectionLabel(this.label,
      {super.key, this.highlighted = false, this.subtitle});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        color: highlighted
            ? kBrandColor.withValues(alpha: 0.10)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Board section heading: 24/800 with tight tracking.
            Text(
              label,
              style: DesktopTokens.section(GoogleFonts.getFont(
                  currentFontFamily,
                  color: kTextColor,
                  letterSpacing: -0.5)),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kStatusText, fontSize: 13, height: 18 / 13),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      );
}

class _PerformanceTile extends StatefulWidget {
  const _PerformanceTile();

  @override
  State<_PerformanceTile> createState() => _PerformanceTileState();
}

/// Performance-profile picker (brief §3A): Auto / Performance / Balanced /
/// Quality, each with a live summary of the effects it actually changes.
class _PerformanceTileState extends State<_PerformanceTile> {
  ShuroProfile _choice = ShuroProfile.auto;
  ShuroProfile _effective = ShuroProfile.balanced;
  DeviceClass? _deviceClass;
  int? _ramMb;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final r = await DeviceProfileService.resolve();
    if (!mounted) return;
    setState(() {
      _choice = r.choice;
      _effective = r.effective;
      _deviceClass = r.deviceClass;
      _ramMb = r.totalRamMb;
    });
  }

  String get _subtitle {
    final preset = DeviceProfileService.presetFor(_effective);
    final label =
        _choice == ShuroProfile.auto ? 'Auto → ${preset.name}' : preset.name;
    return '$label · ${DeviceProfileService.describeDevice(_ramMb, _deviceClass)}';
  }

  Future<void> _openSheet(BuildContext context) async {
    final appearance = context.read<AppearanceSettings>();
    final appState = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => ScrollSafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Performance profile',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Auto picks a preset from this device (${DeviceProfileService.describeDevice(_ramMb, _deviceClass)}). Choosing a preset applies it instantly.',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, fontSize: 12),
              ),
              const SizedBox(height: 10),
              for (final profile in ShuroProfile.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    profile == _choice
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: profile == _choice ? kBrandColor : kMutedTextColor,
                    size: 20,
                  ),
                  title: Text(
                    profile == ShuroProfile.auto
                        ? 'Auto (recommended)'
                        : DeviceProfileService.presetFor(profile).name,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    profile == ShuroProfile.auto
                        ? 'Follows this device: currently ${DeviceProfileService.presetFor(_effective).name}'
                        : DeviceProfileService.presetFor(profile).tagline,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 11.5),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await DeviceProfileService.apply(
                      profile,
                      appearance,
                      setReduceAnimations: appState.updateReduceAnimations,
                    );
                    await _refresh();
                  },
                ),
              const Divider(color: kDividerColor, height: 18),
              Text('What this changes',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final line
                  in DeviceProfileService.presetFor(_effective).changes)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('· $line',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white70, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _NavRow(
      icon: Icons.speed_rounded,
      label: 'Performance profile',
      value: _subtitle,
      onTap: () => _openSheet(context),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  /// One-line explainer under the label (Settings board rows: 12/kStatusText).
  final String? description;

  /// Null means this row is informational only — no ripple, no chevron,
  /// nothing happens on tap, instead of a row that looks tappable but
  /// silently does nothing.
  final VoidCallback? onTap;
  final bool destructive;

  const _NavRow(
      {required this.icon,
      required this.label,
      this.onTap,
      this.value,
      this.description,
      this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFFCA5A5) : kTextColor;
    final tappable = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: _HoverRow(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: destructive ? const Color(0xFFFCA5A5) : kMuted2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: color,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(description!,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText,
                              fontSize: 12,
                              height: 16 / 12)),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                tappable
                    ? _ValuePill(value!)
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          value!,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText, fontSize: 12),
                        ),
                      ),
              ] else if (tappable)
                const Icon(Icons.chevron_right_rounded,
                    color: kMuted2, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// The board's value control: a bordered pill showing the current value with
/// a dropdown chevron, right-aligned in the row.
class _ValuePill extends StatelessWidget {
  final String value;
  const _ValuePill(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kNavText, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 14, color: kMuted2),
        ],
      ),
    );
  }
}

/// Row hover per the boards: white 4.5% rounded fill over 120 ms.
class _HoverRow extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _HoverRow({required this.onTap, required this.child});

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;
    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: ShuroMotion.std,
        decoration: BoxDecoration(
          color: _hover && tappable
              ? Colors.white.withValues(alpha: 0.045)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: tappable
            ? InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(10),
                child: widget.child,
              )
            : widget.child,
      ),
    );
  }
}

/// Artwork cache + "Clear cache", backed by Flutter's own real image
/// cache (`PaintingBinding.instance.imageCache`) instead of a hardcoded
/// number — the only cache this app actually keeps (there's no separate
/// audio cache distinct from Downloads, which already has its own real,
/// wired "Clear downloads" row above). A StatefulWidget of its own so
/// clearing the cache can refresh the displayed size immediately, without
/// routing an unrelated piece of state through AppState for it.
class _CacheSection extends StatefulWidget {
  const _CacheSection();

  @override
  State<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends State<_CacheSection> {
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '${(bytes / 1024).ceil()} KB';
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  void _clear() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cache = PaintingBinding.instance.imageCache;
    return _SettingsGroupCard(
      title: 'CACHE & STORAGE',
      rows: [
        _NavRow(
            icon: Icons.image_rounded,
            label: 'Artwork cache',
            value: _formatBytes(cache.currentSizeBytes)),
        _NavRow(
          icon: Icons.cleaning_services_rounded,
          label: 'Clear cache',
          description: 'Cached artwork is re-fetched as needed.',
          destructive: true,
          onTap: () => showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: kCardColor,
              title: Text('Clear cache?',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white, fontSize: 16)),
              content: Text(
                  'Cached artwork will be re-fetched as needed. Downloaded songs are not affected.',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kMutedTextColor, fontSize: 13)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _clear();
                    showSuccessSnackBar(context, 'Cleared');
                  },
                  child: const Text('Clear',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// One-line explainer under the label (Settings board rows).
  final String? description;

  const _ToggleRow(
      {required this.label,
      required this.value,
      required this.onChanged,
      this.description});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: _HoverRow(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(description!,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText,
                              fontSize: 12,
                              height: 16 / 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _BoardSwitch(value: value, onChanged: onChanged, label: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// The board's 44x26 switch: violet track when on, white 18% when off, a
/// 20 px knob sliding on the 120 ms std curve. Semantics stay a real toggle
/// so screen readers (and tests) see switch state; the whole row taps too.
class _BoardSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  const _BoardSwitch(
      {required this.value, required this.onChanged, this.label});

  @override
  Widget build(BuildContext context) {
    final duration =
        reduceMotionEnabled ? Duration.zero : const Duration(milliseconds: 120);
    return Semantics(
      toggled: value,
      button: true,
      label: label,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: duration,
          curve: ShuroMotion.std,
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: value ? kBrandColor : Colors.white.withValues(alpha: 0.18),
          ),
          child: AnimatedAlign(
            duration: duration,
            curve: ShuroMotion.spring,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small muted caption under a row — used for one-line explanations
/// (the reset section's warning).
class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 24, 6),
        child: Text(
          text,
          style: GoogleFonts.getFont(currentFontFamily,
              color: kStatusText, fontSize: 12, height: 16 / 12),
        ),
      );
}

/// Filter-as-you-type index over the settings sections. Returns the section id
/// the user picked, or null. Deliberately does not search individual rows: a
/// section jump is honest about where it lands, whereas a row-level index
/// would break the moment a row is reworded.
class _SettingsSearchDialog extends StatefulWidget {
  final List<({String id, String title, String keywords})> index;

  const _SettingsSearchDialog({required this.index});

  @override
  State<_SettingsSearchDialog> createState() => _SettingsSearchDialogState();
}

class _SettingsSearchDialogState extends State<_SettingsSearchDialog> {
  String _query = '';

  List<({String id, String title, String keywords})> get _matches {
    if (_query.isEmpty) return widget.index;
    final q = _query.toLowerCase();
    return widget.index
        .where(
            (e) => e.title.toLowerCase().contains(q) || e.keywords.contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Dialog(
      backgroundColor: kCardColor,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 110, left: 28, right: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                autofocus: true,
                cursorColor: kBrandColor,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kTextColor, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: Colors.white38),
                  hintText: 'Find a setting…',
                  hintStyle: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white30, fontSize: 14),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            const Divider(height: 1, color: Color(0x14FFFFFF)),
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Text('Nothing matches “$_query”',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white38, fontSize: 13)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final entry = matches[i];
                    return ListTile(
                      dense: true,
                      title: Text(entry.title,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kTextColor, fontSize: 13.5)),
                      subtitle: _query.isEmpty
                          ? null
                          : Text(entry.keywords,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: Colors.white30, fontSize: 10.5)),
                      trailing: const Icon(Icons.arrow_forward_rounded,
                          size: 15, color: Colors.white24),
                      onTap: () => Navigator.of(context).pop(entry.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chooses the desktop two-pane settings layout or the mobile scroll.
class _SettingsBody extends StatelessWidget {
  final List<Widget> sections;
  final ValueNotifier<String> selected;

  const _SettingsBody(this.sections, {required this.selected});

  @override
  Widget build(BuildContext context) {
    final desktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (!desktop) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section entrances: fade + rise, staggered per the motion kit
            // (settled immediately under reduced motion).
            for (final (i, section) in sections.indexed)
              Entrance(delay: Entrance.stagger(i), child: section),
          ],
        ),
      );
    }
    return _TwoPaneSettings(sections: sections, selected: selected);
  }
}

/// Desktop settings: a 220 px section rail with its own filter, and one
/// section of content at a time (design doc: "Two panes", content max 720 px).
/// Sections are recognised inside the shared widget list by their
/// `_SectionLabel`, so the rows themselves exist exactly once.
class _TwoPaneSettings extends StatefulWidget {
  final List<Widget> sections;
  final ValueNotifier<String> selected;

  const _TwoPaneSettings({required this.sections, required this.selected});

  @override
  State<_TwoPaneSettings> createState() => _TwoPaneSettingsState();
}

class _TwoPaneSettingsState extends State<_TwoPaneSettings> {
  String _query = '';
  String _selected = 'account';

  @override
  void initState() {
    super.initState();
    _selected = widget.selected.value;
    widget.selected.addListener(_onExternalSelect);
  }

  @override
  void dispose() {
    widget.selected.removeListener(_onExternalSelect);
    super.dispose();
  }

  void _onExternalSelect() {
    if (!mounted) return;
    setState(() => _selected = widget.selected.value);
  }

  void _select(String id) {
    setState(() => _selected = id);
    widget.selected.value = id;
  }

  /// Splits the flat list into the page header (everything before the first
  /// section label: title, search field, actions) and id -> rows. The header
  /// used to be dropped here, which made the page title and "Find a setting"
  /// disappear on desktop.
  (List<Widget>, Map<String, List<Widget>>) _split() {
    final byTitle = <String, String>{
      for (final entry in _SettingsScreenState.index)
        entry.title.toUpperCase(): entry.id,
    };
    final header = <Widget>[];
    final groups = <String, List<Widget>>{};
    String? current;
    for (final widget in widget.sections) {
      if (widget is _SectionLabel) {
        final id = byTitle[widget.label.toUpperCase()];
        current = id;
        // The label stays in the group: in the two-pane layout it is the
        // heading of the content pane.
        if (id != null) groups.putIfAbsent(id, () => []).add(widget);
        continue;
      }
      if (current == null) {
        header.add(widget);
      } else {
        groups.putIfAbsent(current, () => []).add(widget);
      }
    }
    return (header, groups);
  }

  /// Fixed order of the settings rail: sections live in groups, destructive
  /// items last.
  static const _railGroups = <(String, List<String>)>[
    ('User', ['account']),
    ('Look & feel', ['appearance', 'lyrics', 'behavior']),
    ('Playback & audio', ['playback', 'audio']),
    ('Library & server', ['downloads', 'cache', 'server']),
    ('System', ['performance', 'listenbrainz', 'about', 'reset']),
  ];

  /// Rail icons per section (Settings board nav).
  static const _sectionIcons = <String, IconData>{
    'account': Icons.person_rounded,
    'playback': Icons.play_arrow_rounded,
    'audio': Icons.graphic_eq_rounded,
    'lyrics': Icons.lyrics_rounded,
    'downloads': Icons.download_rounded,
    'cache': Icons.storage_rounded,
    'appearance': Icons.palette_rounded,
    'behavior': Icons.tune_rounded,
    'server': Icons.dns_rounded,
    'reset': Icons.restart_alt_rounded,
    'performance': Icons.speed_rounded,
    'listenbrainz': Icons.query_stats_rounded,
    'about': Icons.info_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final (header, groups) = _split();
    final entries = _SettingsScreenState.index.where((entry) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return entry.title.toLowerCase().contains(q) ||
          entry.keywords.contains(q);
    }).toList();
    if (!groups.containsKey(_selected) && groups.isNotEmpty) {
      _selected = groups.keys.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The page header keeps its full width above both panes.
        ...header,
        const Divider(height: 1, thickness: 1, color: kDividerColor),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: TextField(
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor, fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: kRaisedColor,
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 16, color: kMuted2),
                          hintText: 'Search settings',
                          hintStyle: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText, fontSize: 12.5),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: kGlass)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: kVioletLight.withValues(alpha: 0.5))),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          // The rail is organised in fixed groups (native-app
                          // convention); search filters within them.
                          for (final group in _railGroups)
                            if (entries
                                .any((e) => group.$2.contains(e.id))) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 4),
                                child: Text(group.$1.toUpperCase(),
                                    style: GoogleFonts.getFont(
                                        currentFontFamily,
                                        color: kMuted2,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8)),
                              ),
                              for (final entry in entries)
                                if (group.$2.contains(entry.id))
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 1),
                                    child: Material(
                                      color: entry.id == _selected
                                          ? kBrandColor.withValues(alpha: 0.18)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => _select(entry.id),
                                        child: Container(
                                          height: 38,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Row(
                                            children: [
                                              // Active marker: the 3x20 violet bar
                                              // from the sidebar boards.
                                              Container(
                                                width: 3,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  color: entry.id == _selected
                                                      ? kBrandColor
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                _sectionIcons[entry.id] ??
                                                    Icons.settings_rounded,
                                                size: 18,
                                                color: entry.id == _selected
                                                    ? kVioletLight
                                                    : kMuted2,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(entry.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.getFont(
                                                        currentFontFamily,
                                                        color: entry.id ==
                                                                _selected
                                                            ? Colors.white
                                                            : kNavText,
                                                        fontSize: 14,
                                                        fontWeight: entry.id ==
                                                                _selected
                                                            ? FontWeight.w600
                                                            : FontWeight.w500)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                            ], // close group spread
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, color: kDividerColor),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  child: DesktopContentFrame(
                    maxWidth: DesktopTokens.contentSettings,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The label doubles as the pane heading. Each block
                        // enters with the motion kit's staggered entrance
                        // (one-shot; settled under reduced motion).
                        for (final (i, section)
                            in (groups[_selected] ?? const <Widget>[]).indexed)
                          Entrance(
                            key: ValueKey('$_selected-$i'),
                            delay: Entrance.stagger(i),
                            child: section,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Board-styled group: a 12/600 muted label above a raised card (radius 16,
/// hairline border) whose rows are split by hairlines (Settings board).
class _SettingsGroupCard extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const _SettingsGroupCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMuted2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: kRaisedColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  // Hairlines only between consecutive rows, so captions
                  // tucked between rows don't grow stray rules.
                  if (i > 0 && _isRow(rows[i]) && _isRow(rows[i - 1]))
                    Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withValues(alpha: 0.06)),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _isRow(Widget w) =>
      w is _NavRow || w is _ToggleRow || w is _PerformanceTile;
}

/// SettingsAudio board: the live signal-path card. A vertical chain
/// Source -> Server/Local -> Transcode -> Output, drawn only from what the
/// diagnostics layer can actually prove (audio_diagnostics.dart): it never
/// claims "bit-perfect". Active nodes pulse a violet 25% halo; the loop
/// freezes under reduced motion.
class _SignalPathCard extends StatefulWidget {
  const _SignalPathCard();

  @override
  State<_SignalPathCard> createState() => _SignalPathCardState();
}

class _SignalPathCardState extends State<_SignalPathCard> {
  @override
  void initState() {
    super.initState();
    // Read-only reuse of the shared monitor: fills the Output node when the
    // native bridge exists and answers `unknown` everywhere else. The call
    // is cached by the monitor itself, so opening Settings is cheap.
    // ignore: discarded_futures
    sharedAudioCapabilityMonitor.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return ListenableBuilder(
      // Route/capability changes (headphones plugged, DAC attached) arrive
      // through the shared monitor; song/policy changes through the player.
      listenable: sharedAudioCapabilityMonitor,
      builder: (context, _) {
        final diagnostics = player.getOutputDiagnostics();
        final song = player.currentSong;
        return _card(context, song, diagnostics);
      },
    );
  }

  Widget _card(BuildContext context, Song? song, AudioDiagnostics? d) {
    final lossless = _isLossless(d);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: kRaisedColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kHairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.graphic_eq_rounded,
                      size: 16, color: kVioletLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      song == null
                          ? 'Signal path, live'
                          : 'Now playing: ${song.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kTextColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (lossless)
                    _PillChip(
                      text: 'LOSSLESS',
                      color: kGreen,
                      textColor: kGreenLight,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (song == null || d == null)
                Text(
                  'Nothing is playing. The live path from source to output appears once a track starts.',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 12, height: 16 / 12),
                )
              else ...[
                // The same evidence-bounded summary Now Playing reports.
                Text(d.signalPathSummary,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kStatusText, fontSize: 12, height: 16 / 12)),
                const SizedBox(height: 16),
                _chain(d),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The vertical chain. `active` nodes take part in the current path and
  /// pulse; inactive ones (a transcode stage that isn't in use) sit grey.
  Widget _chain(AudioDiagnostics d) {
    final transcoded = d.source.streamMode == StreamMode.transcoded;
    final nodes = <({String label, String sub, bool active})>[
      (
        label: 'Source',
        sub: _sourceLabel(d),
        active: true,
      ),
      (
        label:
            d.source.sourceKind == SourceKind.local ? 'Local file' : 'Server',
        sub: d.source.sourceKind == SourceKind.local
            ? 'On this device'
            : 'Navidrome',
        active: true,
      ),
      (
        label: 'Transcode',
        sub: transcoded ? 'Server is transcoding' : 'Original stream',
        active: transcoded,
      ),
      (
        label: 'Output',
        sub: _outputLabel(d),
        active: true,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < nodes.length; i++) ...[
          if (i > 0) const _ChainLink(),
          Row(
            children: [
              _PulseDot(active: nodes[i].active),
              const SizedBox(width: 12),
              Text(nodes[i].label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: nodes[i].active ? kTextColor : kMuted2,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(nodes[i].sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2, fontSize: 12)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// e.g. `FLAC · 24-bit · 96 kHz`, or `Format not reported`.
  String _sourceLabel(AudioDiagnostics d) {
    final parts = <String>[];
    final codec = d.source.codec?.trim();
    if (codec != null && codec.isNotEmpty) parts.add(codec.toUpperCase());
    final depth = d.source.bitDepth;
    if (depth != null) parts.add('$depth-bit');
    final rate = d.source.sampleRateHz;
    if (rate != null) {
      parts.add(rate % 1000 == 0
          ? '${rate ~/ 1000} kHz'
          : '${(rate / 1000).toStringAsFixed(1)} kHz');
    }
    if (parts.isEmpty) return 'Format not reported';
    return parts.join(' · ');
  }

  String _outputLabel(AudioDiagnostics d) => switch (d.route.kind) {
        RouteKind.builtIn => 'Built-in output',
        RouteKind.wired => 'Wired output',
        RouteKind.bluetooth => 'Bluetooth',
        RouteKind.usb => d.route.deviceLabel ?? 'USB audio device',
        RouteKind.other => d.route.deviceLabel ?? 'Other route',
        RouteKind.unknown => 'Route not reported',
      };

  /// Lossless is only claimed from evidence: a lossless codec that the
  /// server did not transcode.
  bool _isLossless(AudioDiagnostics? d) {
    if (d == null) return false;
    final codec = d.source.codec?.trim().toLowerCase();
    if (codec == null || codec.isEmpty) return false;
    const lossless = {
      'flac',
      'alac',
      'wav',
      'wave',
      'aiff',
      'aif',
      'ape',
      'wv',
      'dsf',
      'dff',
    };
    return lossless.contains(codec) &&
        d.source.streamMode != StreamMode.transcoded;
  }
}

/// A chain node's dot: 10 px core in a 26 px field. Active dots pulse a
/// violet 25% halo (loop); under reduced motion the halo renders once and
/// holds. Inactive nodes are plain grey.
class _PulseDot extends StatefulWidget {
  final bool active;

  const _PulseDot({required this.active});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000));

  @override
  void initState() {
    super.initState();
    if (widget.active && !reduceMotionEnabled) _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox(
        width: 26,
        height: 26,
        child: Center(
          child: SizedBox(
            width: 10,
            height: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white24,
              ),
            ),
          ),
        ),
      );
    }
    if (reduceMotionEnabled) {
      // Frozen: the halo stays visible so the state still reads.
      return const SizedBox(
        width: 26,
        height: 26,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x407C3AED), // violet 25%
          ),
          child: Center(
            child: SizedBox(
              width: 10,
              height: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kBrandColor,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 26,
      height: 26,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          return Center(
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 16 + 10 * t,
                  height: 16 + 10 * t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kBrandColor.withValues(alpha: 0.25 * (1 - t)),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kBrandColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The short vertical rule joining two chain nodes, aligned under the dots.
class _ChainLink extends StatelessWidget {
  const _ChainLink();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Container(
        width: 2,
        height: 12,
        color: Colors.white.withValues(alpha: 0.12),
      ),
    );
  }
}

/// Small pill chip (status badges: LOSSLESS, Connected, …).
class _PillChip extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _PillChip(
      {required this.text, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: GoogleFonts.getFont(currentFontFamily,
              color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
