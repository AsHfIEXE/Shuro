import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_info.dart';
import '../../models/download_state.dart';
import '../../playback/event_log.dart';
import '../../backend/subsonic_api.dart';
import '../../services/server_secret_store.dart';
import '../../services/device_profile.dart';
import '../../services/download_service.dart';
import '../../services/playback_prefs.dart';
import '../../state/app_state.dart';
import '../../state/appearance_settings.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/state_views.dart';
import 'artwork_style_sheet.dart';
import 'avatar_editor_screen.dart';
import 'font_picker_sheet.dart';
import 'manage_servers_screen.dart';
import 'quality_selector_sheet.dart';
import '../onboarding/consent_screen.dart' show LegalTexts, DeviceBasics;

import '../../widgets/page_transitions.dart';
/// "14. Settings" — Account / Playback / Downloads / Cache / Appearance /
/// Behavior / About, per the requested structure.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Settings', style: headingFont(color: kTextColor, fontSize: 22, fontWeight: FontWeight.w600)),
            ),

            _SectionLabel('ACCOUNT'),
            _NavRow(
              icon: Icons.dns_rounded,
              label: 'Server',
              value: appState.activeServer?.name ?? (appState.isLocalOnly ? 'Local files only' : '—'),
              onTap: () => Navigator.of(context).push(drillDownRoute(const ManageServersScreen())),
            ),
            if (appState.hasServer)
              // No tap affordance: there's no separate "account" page to
              // open (the server connection *is* the account), so this is
              // honest info display rather than a dead button.
              _NavRow(icon: Icons.person_rounded, label: 'Account', value: appState.activeServer?.username ?? '—'),
            _NavRow(
              icon: Icons.photo_camera_rounded,
              label: 'Profile photo',
              value: appState.userAvatarBytes != null ? 'Set' : 'Default',
              onTap: () => Navigator.of(context).push(drillDownRoute(const AvatarEditorScreen())),
            ),
            _NavRow(
              icon: Icons.logout_rounded,
              // A local-only user never actually signed into anything, so
              // the destructive action here is framed as leaving that mode
              // (back to the Welcome screen) rather than a mismatched
              // "sign out" that implies an account session that never
              // existed.
              label: appState.isLocalOnly ? 'Exit local-only mode' : 'Sign out',
              destructive: true,
              onTap: () => _confirmSignOut(context, isLocalOnly: appState.isLocalOnly),
            ),

            _SectionLabel('PLAYBACK'),
            _NavRow(
              icon: Icons.wifi_rounded,
              label: 'Wi-Fi quality',
              value: appState.wifiQuality.label,
              onTap: () async {
                final selected = await showQualitySelectorSheet(context, title: 'Wi-Fi Streaming Quality', current: appState.wifiQuality);
                if (selected != null) appState.updateWifiQuality(selected);
              },
            ),
            _NavRow(
              icon: Icons.signal_cellular_alt_rounded,
              label: 'Mobile data quality',
              value: appState.mobileQuality.label,
              onTap: () async {
                final selected = await showQualitySelectorSheet(context, title: 'Mobile Data Streaming Quality', current: appState.mobileQuality);
                if (selected != null) appState.updateMobileQuality(selected);
              },
            ),
            // Effects that change real audio, each reading PlaybackPrefs.
            //
            // Fade between songs is a real volume fade across the boundary.
            // Gapless playback deliberately has no switch: the whole queue is
            // handed to the engine as one playlist (see PlayerController
            // _jumpTo), so consecutive tracks run into each other with no load
            // gap by construction rather than by a setting.
            _NavRow(
              icon: Icons.graphic_eq_rounded,
              label: 'Fade between songs',
              value: playbackPrefs.crossfadeSeconds == 0 ? 'Off' : '${playbackPrefs.crossfadeSeconds}s',
              onTap: () => _pickCrossfade(context, playbackPrefs),
            ),
            // Loudness normalisation from the server's own ReplayGain tags.
            _ToggleRow(
              label: 'Replay gain',
              value: playbackPrefs.replayGain,
              onChanged: (v) => playbackPrefs.setReplayGain(v),
            ),
            _NavRow(
              icon: Icons.speed_rounded,
              label: 'Playback speed',
              value: '${playbackPrefs.playbackSpeed.toStringAsFixed(2)}×',
              onTap: () => _pickPlaybackSpeed(context, playbackPrefs),
            ),
            _ToggleRow(
              label: 'Skip silence',
              value: playbackPrefs.skipSilence,
              onChanged: (v) => playbackPrefs.setSkipSilence(v),
            ),

            _SectionLabel('LYRICS'),
            _ToggleRow(label: 'Auto-scroll', value: appState.lyricsAutoScroll, onChanged: appState.updateLyricsAutoScroll),
            _NavRow(
              icon: Icons.sync_rounded,
              label: 'Sync adjustment',
              value: appState.lyricsOffsetMs == 0 ? 'On time' : '${appState.lyricsOffsetMs > 0 ? '+' : ''}${appState.lyricsOffsetMs} ms',
              onTap: () => _adjustLyricsSync(context, appState),
            ),

            _SectionLabel('DOWNLOADS'),
            _NavRow(
              icon: Icons.download_rounded,
              label: 'Download quality',
              value: appState.downloadQuality.label,
              onTap: () async {
                final selected = await showQualitySelectorSheet(context, title: 'Download Quality', current: appState.downloadQuality);
                if (selected != null) appState.updateDownloadQuality(selected);
              },
            ),
            _ToggleRow(label: 'Wi-Fi only', value: appState.downloadWifiOnly, onChanged: (v) => appState.toggleSetting(() => appState.downloadWifiOnly = v)),
            // Wired to the real download service: opens the system folder
            // picker, and the chosen folder becomes where downloads are saved.
            // "App storage" means the default documents dir (which survives
            // app updates).
            _NavRow(
              icon: Icons.folder_rounded,
              label: 'Storage location',
              value: context.watch<DownloadService>().customLocation == null ? 'App storage' : 'Custom folder',
              onTap: () => _pickDownloadLocation(context),
            ),
            _NavRow(
              icon: Icons.delete_outline_rounded,
              label: 'Clear downloads',
              destructive: true,
              onTap: () => _confirmClear(
                context,
                title: 'Clear all downloads?',
                message: "You'll need to download songs again to play them offline.",
                onConfirm: () async {
                  final downloads = context.read<DownloadService>();
                  for (final song in downloads.songs) {
                    await downloads.remove(song.id);
                  }
                },
              ),
            ),

            _SectionLabel('CACHE'),
            const _CacheSection(),

            _SectionLabel('APPEARANCE'),
            // No tap affordance: Shuro is deliberately dark-only (part of
            // its brand identity, not an oversight), so there's no picker
            // to open — this states that rather than pretending to offer one.
            _NavRow(icon: Icons.dark_mode_rounded, label: 'Theme', value: 'Dark'),
            _NavRow(icon: Icons.text_fields_rounded, label: 'Font', value: appState.fontFamily, onTap: () => showFontPickerSheet(context)),
            _ToggleRow(label: 'Dynamic colors', value: appState.dynamicColors, onChanged: (v) => appState.toggleSetting(() => appState.dynamicColors = v)),
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
            _ToggleRow(label: 'Reduce animations', value: appState.reduceAnimations, onChanged: appState.updateReduceAnimations),
            _NavRow(
              icon: Icons.grid_view_rounded,
              label: 'Artwork style',
              value: appState.artworkStyle.label,
              onTap: () async {
                final selected = await showArtworkStyleSheet(context, appState.artworkStyle);
                if (selected != null) appState.updateArtworkStyle(selected);
              },
            ),

            _SectionLabel('BEHAVIOR'),
            _ToggleRow(label: 'Autoplay', value: appState.autoplay, onChanged: (v) => appState.toggleSetting(() => appState.autoplay = v)),
            _ToggleRow(label: 'Remember queue', value: appState.rememberQueue, onChanged: (v) => appState.toggleSetting(() => appState.rememberQueue = v)),
            _ToggleRow(label: 'Resume playback', value: appState.resumePlayback, onChanged: (v) => appState.toggleSetting(() => appState.resumePlayback = v)),

            const _SectionLabel('SERVER'),
            _NavRow(
              icon: Icons.sync_rounded,
              label: 'Rescan server library',
              value: 'Ask Navidrome to look for new files',
              onTap: () => _rescanServer(context),
            ),

            const _SectionLabel('RESET'),
            _NavRow(
              icon: Icons.restart_alt_rounded,
              label: 'Reset app data',
              value: 'Erase everything',
              destructive: true,
              onTap: () => _confirmResetApp(context),
            ),
            const _Note(
              'Signs out, forgets servers, favorites, playlists, downloads and every setting, '
              'then closes the app. Nothing on your Navidrome server is touched.',
            ),

            const _SectionLabel('PERFORMANCE'),
            const _PerformanceTile(),

            const _SectionLabel('ABOUT'),
            const _AboutBlock(),
            _NavRow(icon: Icons.info_outline_rounded, label: 'Version', value: kAppVersion),
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
            const SizedBox(height: 32),
          ],
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report a problem', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'The last ${PlaybackEventLog.kMaxEvents} playback events, redacted — no credentials, no URLs. Copy it and send it when a bug appears.',
                style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
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
                      style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 11, height: 1.35),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Device & app info', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final row in [...basics.entries, ...screen.entries])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(row.key, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12.5)),
                      Text(row.value, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
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
        child: Text(body, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 13, height: 1.55)),
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
        title: Text('Reset app data?', style: GoogleFonts.getFont(currentFontFamily, color: kTextColor, fontWeight: FontWeight.w600)),
        content: Text(
          'This erases everything stored on this device: servers, favorites, playlists, downloads, lyrics settings and preferences. '
          'Your music on the server is not touched.',
          style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Erase everything', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('App data cleared', style: GoogleFonts.getFont(currentFontFamily, color: kTextColor, fontWeight: FontWeight.w600)),
            content: Text(
              'Everything stored by Shuro was erased. Reload the page to start fresh.',
              style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13.5, height: 1.45),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK', style: TextStyle(color: kBrandColor, fontWeight: FontWeight.w600)),
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
  void _pickBackgroundStyle(BuildContext context, AppearanceSettings appearance) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Now Playing background', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            for (final style in BackgroundStyle.values)
              ListTile(
                leading: Icon(
                  style == appearance.backgroundStyle ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: style == appearance.backgroundStyle ? kBrandColor : kMutedTextColor,
                ),
                title: Text(
                  switch (style) {
                    BackgroundStyle.animatedBlur => 'Animated blur',
                    BackgroundStyle.animatedGradient => 'Animated gradient',
                    BackgroundStyle.staticArtwork => 'Static artwork colours',
                  },
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
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
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
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
      builder: (sheetContext) => SafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final value = appearance.backdropBlurScale;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 18),
                  Text('Background blur', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'How strongly the artwork is blurred behind Now Playing and Lyrics. Open Now Playing to see the change live.',
                    style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
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
                      style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
  void _pickBackdropMotion(BuildContext context, AppearanceSettings appearance) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Background motion', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            for (final motion in BackdropMotion.values)
              ListTile(
                leading: Icon(
                  appearance.backdropMotion == motion ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: appearance.backdropMotion == motion ? kBrandColor : kMutedTextColor,
                ),
                title: Text(
                  switch (motion) {
                    BackdropMotion.still => 'Still',
                    BackdropMotion.subtle => 'Subtle',
                    BackdropMotion.normal => 'Normal (default)',
                    BackdropMotion.lively => 'Fast',
                  },
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  switch (motion) {
                    BackdropMotion.still => 'The artwork holds completely still',
                    BackdropMotion.subtle => 'Barely-there drift — slower and shallower than default',
                    BackdropMotion.normal => 'The designed slow breathe (18-second cycle)',
                    BackdropMotion.lively => 'Fast drifting colours — clearly visible motion',
                  },
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
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
  void _pickLyricsHighlight(BuildContext context, AppearanceSettings appearance) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Lyrics highlight', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            for (final mode in LyricsHighlight.values)
              ListTile(
                leading: Icon(
                  appearance.lyricsHighlight == mode ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: appearance.lyricsHighlight == mode ? kBrandColor : kMutedTextColor,
                ),
                title: Text(
                  switch (mode) {
                    LyricsHighlight.word => 'Word by word',
                    LyricsHighlight.line => 'Line by line',
                  },
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  switch (mode) {
                    LyricsHighlight.word => 'Each word lights up as it is sung — karaoke style',
                    LyricsHighlight.line => 'The whole line lights up at once — no word fill',
                  },
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
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
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Fade between songs', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              for (final seconds in const [0, 2, 4, 6])
                ListTile(
                  leading: Icon(
                    prefs.crossfadeSeconds == seconds ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: prefs.crossfadeSeconds == seconds ? kBrandColor : kMutedTextColor,
                  ),
                  title: Text(
                    seconds == 0 ? 'Off' : '${seconds}s fade',
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    seconds == 0 ? 'Songs switch at full volume' : 'Each song fades out over its last ${seconds}s',
                    style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
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
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Playback speed', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            for (final speed in const [0.75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                leading: Icon(
                  prefs.playbackSpeed == speed ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: prefs.playbackSpeed == speed ? kBrandColor : kMutedTextColor,
                ),
                title: Text(
                  '${speed.toStringAsFixed(2)}×',
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
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
      SnackBar(content: Text(path == null ? 'No folder chosen — downloads stay in app storage.' : 'Downloads will be saved to: $path')),
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
      showSuccessSnackBar(context, 'Rescan started — the server knows ${status.count} files so far.');
    }).catchError((_) {
      if (context.mounted) showErrorSnackBar(context, 'Could not reach the server.');
    });
  }

  /// Chooses the karaoke fill renderer for the lyrics screen.
  /// What each remote service is used for. These are services, not code —
  /// they carry no licence obligations like pub packages do, but naming them
  /// is the honest thing to do and costs one page.
  static const List<({String name, String usage})> _serviceEntries = [
    (name: 'LRCLIB (lrclib.net)', usage: 'Synced and unsynced lyrics, including word-level timing where contributors recorded it.'),
    (name: 'Last.fm / Libre.fm', usage: 'Optional scrobbling — reporting the tracks you play to the account you authorize yourself. Uses the AudioScrobbler protocol.'),
    (name: 'MusicBrainz', usage: 'Album and artist metadata enrichment, and cover-art lookups when your server has no artwork.'),
    (name: 'Cover Art Archive', usage: 'Album artwork for releases identified through MusicBrainz.'),
    (name: 'Navidrome / OpenSubsonic', usage: 'Your own music server — the Subsonic API it speaks is what Shuro is built around.'),
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
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text('Services & data sources', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Shuro talks to your own Navidrome server, and to these open services for extras. Each is used only for the purpose listed, and only when you use the matching feature.',
              style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final entry in _serviceEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(entry.usage, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
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
            title: Text('Sync adjustment', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  offset.value == 0
                      ? 'On time'
                      : '${offset.value > 0 ? '+' : ''}${offset.value} ms — lyrics appear ${offset.value > 0 ? 'sooner' : 'later'}',
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white70),
                      onPressed: () => setDialogState(() => offset.value -= 100),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text('${offset.value} ms', textAlign: TextAlign.center, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70),
                      onPressed: () => setDialogState(() => offset.value += 100),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => setDialogState(() => offset.value = 0), child: const Text('Reset')),
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
        title: Text(isLocalOnly ? 'Exit local-only mode?' : 'Sign out?', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
        content: Text(
          isLocalOnly
              ? "You'll go back to the start screen. Your imported local files stay on this device."
              : "You'll need to reconnect to your server to use the app again.",
          style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<AppState>().disconnect();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text(isLocalOnly ? 'Exit' : 'Sign out', style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, {required String title, required String message, required VoidCallback onConfirm}) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text(title, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
        content: Text(message, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
              showSuccessSnackBar(context, 'Cleared');
            },
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
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
                  Text(kAppName, style: headingFont(color: kTextColor, fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(kAppTagline, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(kAppDescription, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 10),
          Text(kAppTaglineAlt, style: GoogleFonts.getFont(currentFontFamily, color: kTextColor.withOpacity(0.7), fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Row(
          children: [
            Text(label, style: GoogleFonts.getFont(currentFontFamily, color: kBrandColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
            const SizedBox(width: 10),
            // A hairline runs to the edge — anchors the label so sections read
            // as ruled groups instead of floating captions.
            const Expanded(child: Divider(color: Color(0x14FFFFFF), thickness: 1, height: 1)),
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
    final label = _choice == ShuroProfile.auto
        ? 'Auto → ${preset.name}'
        : preset.name;
    return '$label · ${DeviceProfileService.describeDevice(_ramMb, _deviceClass)}';
  }

  Future<void> _openSheet(BuildContext context) async {
    final appearance = context.read<AppearanceSettings>();
    final appState = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Performance profile', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Auto picks a preset from this device (${DeviceProfileService.describeDevice(_ramMb, _deviceClass)}). Choosing a preset applies it instantly.',
                style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
              ),
              const SizedBox(height: 10),
              for (final profile in ShuroProfile.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    profile == _choice ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: profile == _choice ? kBrandColor : kMutedTextColor,
                    size: 20,
                  ),
                  title: Text(
                    profile == ShuroProfile.auto
                        ? 'Auto (recommended)'
                        : DeviceProfileService.presetFor(profile).name,
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    profile == ShuroProfile.auto
                        ? 'Follows this device: currently ${DeviceProfileService.presetFor(_effective).name}'
                        : DeviceProfileService.presetFor(profile).tagline,
                    style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 11.5),
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
              Text('What this changes', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final line in DeviceProfileService.presetFor(_effective).changes)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('· $line', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 12)),
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
  /// Null means this row is informational only — no ripple, no chevron,
  /// nothing happens on tap, instead of a row that looks tappable but
  /// silently does nothing.
  final VoidCallback? onTap;
  final bool destructive;

  const _NavRow({required this.icon, required this.label, this.onTap, this.value, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent.shade100 : Colors.white;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: destructive ? Colors.redAccent.shade100 : Colors.white70, size: 20),
      title: Text(label, style: GoogleFonts.getFont(currentFontFamily, color: color, fontSize: 14)),
      trailing: value != null
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                value!,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
              ),
            )
          : const Icon(Icons.chevron_right_rounded, color: kMutedTextColor, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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
    return Column(
      children: [
        _NavRow(icon: Icons.image_rounded, label: 'Artwork cache', value: _formatBytes(cache.currentSizeBytes)),
        _NavRow(
          icon: Icons.cleaning_services_rounded,
          label: 'Clear cache',
          destructive: true,
          onTap: () => showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: kCardColor,
              title: Text('Clear cache?', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
              content: Text('Cached artwork will be re-fetched as needed. Downloaded songs are not affected.',
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _clear();
                    showSuccessSnackBar(context, 'Cleared');
                  },
                  child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
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

  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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
          style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 11.5, height: 1.5),
        ),
      );
}
