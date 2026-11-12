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
import '../../services/audio_cache.dart';
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
import '../../models/server_config.dart';
import '../../state/spoken_library_state.dart';
import '../onboarding/server_setup_screen.dart';
import 'settings_prefs.dart';
import '../../services/equalizer_service.dart';
import '../../services/eq_import.dart';
import '../../services/multi_server.dart';
import '../../services/library_cache.dart';
import '../../widgets/click_region.dart';
import '../onboarding/audiobookshelf_setup_screen.dart';

part 'settings_controls.dart';
part 'settings_page_playback.dart';
part 'settings_page_audio.dart';
part 'settings_page_servers.dart';
part 'settings_pages_more.dart';

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
      id: 'servers',
      title: 'Servers and sources',
      keywords:
          'server navidrome audiobookshelf account sign in sign out profile local files add connect'
    ),
    (
      id: 'playback',
      title: 'Playback',
      keywords:
          'how tracks start, transition and end crossfade fade gapless replaygain pre-amp resume scrobble queue speed silence'
    ),
    (
      id: 'audio',
      title: 'Audio and EQ',
      keywords:
          'quality stream streaming bitrate equalizer eq dsp signal path output volume'
    ),
    (
      id: 'library',
      title: 'Library',
      keywords:
          'sync, folders, hidden items, sort defaults, genre display rescan health undo'
    ),
    (
      id: 'lyrics',
      title: 'Lyrics',
      keywords:
          'source order, font size, sync offset default, translation auto-scroll'
    ),
    (
      id: 'downloads',
      title: 'Downloads and offline',
      keywords:
          'quality, folder, wi-fi only, auto-download favorites offline save'
    ),
    (
      id: 'appearance',
      title: 'Appearance',
      keywords:
          'theme, accent, font, density, hero banner on or off dark colour color background immersive animations performance'
    ),
    (
      id: 'desktop',
      title: 'Desktop',
      keywords:
          'tray, start minimized, global shortcuts, media keys, window behaviour'
    ),
    (
      id: 'cache',
      title: 'Storage and cache',
      keywords:
          'cache size, clear cache, image cache, offline usage reset erase data'
    ),
    (
      id: 'integrations',
      title: 'Integrations',
      keywords:
          'last.fm, discord presence, other links listenbrainz scrobble private listening'
    ),
    (
      id: 'pulse',
      title: 'Shuro Pulse',
      keywords: 'taste profile, mix length, reset history'
    ),
    (
      id: 'about',
      title: 'About',
      keywords:
          'version, licenses, logs, report a problem, check for updates terms privacy'
    ),
  ];

  /// The index for this platform: Desktop only exists on desktop.
  static List<({String id, String title, String keywords})> get platformIndex =>
      [
        for (final e in index)
          if (e.id != 'desktop' || _isDesktopPlatform) e,
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
      ValueNotifier<String>('servers');

  Future<void> _openSettingsSearch(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => _SettingsSearchDialog(index: platformIndex),
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
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

      ...serversSection(context, appState),
      ...playbackSection(context, appState, playbackPrefs),
      ...audioSection(context, appState),
      ...librarySection(context, appState),
      ...lyricsSection(context, appState, appearance),
      ...downloadsSection(context, appState),
      ...appearanceSection(context, appState, appearance),
      if (_isDesktopPlatform) ...desktopSection(context),
      ...storageSection(context),
      ...integrationsSection(context, appState),
      ...pulseSection(context, appState),
      ...aboutSection(context),
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
  final AudioCache _songs = AudioCache.instance;

  @override
  void initState() {
    super.initState();
    _songs.addListener(_refresh);
    unawaited(_songs.init());
  }

  @override
  void dispose() {
    _songs.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '${(bytes / 1024).ceil()} KB';
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  String _limitLabel(int mb) => mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';

  void _clearArtwork() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    setState(() {});
  }

  Future<void> _confirm({
    required String title,
    required String body,
    required VoidCallback onConfirm,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text(title,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text(body,
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

  void _pickLimit() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: kCardColor,
        title: Text('Song cache size',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        children: [
          for (final mb in AudioCache.limitChoicesMb)
            RadioListTile<int>(
              value: mb,
              groupValue: _songs.limitMb,
              activeColor: kBrandColor,
              title: Text(_limitLabel(mb),
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kTextColor, fontSize: 14)),
              onChanged: (v) {
                if (v != null) unawaited(_songs.setLimitMb(v));
                Navigator.of(dialogContext).pop();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final art = PaintingBinding.instance.imageCache;
    return Column(
      children: [
        _SettingsGroupCard(
          title: 'SONG CACHE',
          rows: [
            _ToggleRow(
              label: 'Cache songs as you listen',
              description:
                  'Keeps what you play and the next songs in the queue on this device, so replays start instantly and skips never wait.',
              value: _songs.enabled,
              onChanged: (v) => unawaited(_songs.setEnabled(v)),
            ),
            _ToggleRow(
              label: 'Wi-Fi only',
              description: 'Never use mobile data to fill the cache.',
              value: _songs.wifiOnly,
              onChanged: (v) => unawaited(_songs.setWifiOnly(v)),
            ),
            _NavRow(
              icon: Icons.data_usage_rounded,
              label: 'Cache size limit',
              description:
                  'The least recently played songs are removed first.',
              value: _limitLabel(_songs.limitMb),
              onTap: _pickLimit,
            ),
            _NavRow(
                icon: Icons.library_music_rounded,
                label: 'Songs on this device',
                value:
                    '${_formatBytes(_songs.usedBytes)} of ${_limitLabel(_songs.limitMb)}'),
            _NavRow(
              icon: Icons.delete_sweep_rounded,
              label: 'Clear song cache',
              description: 'Downloaded songs are not affected.',
              destructive: true,
              onTap: () => _confirm(
                title: 'Clear song cache?',
                body:
                    'Cached songs will be fetched again the next time you play them. Downloads are not affected.',
                onConfirm: () => unawaited(_songs.clear()),
              ),
            ),
          ],
        ),
        _SettingsGroupCard(
          title: 'ARTWORK',
          rows: [
            _NavRow(
                icon: Icons.image_rounded,
                label: 'Artwork cache',
                value: _formatBytes(art.currentSizeBytes)),
            _NavRow(
              icon: Icons.cleaning_services_rounded,
              label: 'Clear artwork cache',
              description: 'Cached artwork is re-fetched as needed.',
              destructive: true,
              onTap: () => _confirm(
                title: 'Clear artwork cache?',
                body:
                    'Cached artwork will be re-fetched as needed. Downloaded songs are not affected.',
                onConfirm: _clearArtwork,
              ),
            ),
          ],
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
        reduceMotionEnabled ? Duration.zero : const Duration(milliseconds: 200);
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
  String _selected = 'servers';

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
  /// The settings map is one flat list (no group headings).
  static const _railOrder = <String>[
    'servers',
    'playback',
    'audio',
    'library',
    'lyrics',
    'downloads',
    'appearance',
    'desktop',
    'cache',
    'integrations',
    'pulse',
    'about',
  ];

  /// Rail icons per section (Settings board nav).
  static const _sectionIcons = <String, IconData>{
    'servers': Icons.dns_rounded,
    'playback': Icons.play_arrow_rounded,
    'audio': Icons.graphic_eq_rounded,
    'library': Icons.library_music_rounded,
    'lyrics': Icons.lyrics_rounded,
    'downloads': Icons.download_rounded,
    'appearance': Icons.palette_rounded,
    'desktop': Icons.desktop_windows_rounded,
    'cache': Icons.storage_rounded,
    'integrations': Icons.extension_rounded,
    'pulse': Icons.bolt_rounded,
    'about': Icons.info_outline_rounded,
  };

  /// Does [w] contain [q] (lowercase) in a label, description or title?
  static bool _widgetMatches(Widget w, String q) {
    bool has(String? t) => t != null && t.toLowerCase().contains(q);
    if (w is _ControlRow) return has(w.label) || has(w.description);
    if (w is _NavRow) return has(w.label) || has(w.description) || has(w.value);
    if (w is _ToggleRow) return has(w.label) || has(w.description);
    if (w is _SettingsGroupCard) {
      return has(w.title) || w.rows.any((r) => _widgetMatches(r, q));
    }
    return false;
  }

  /// Rows of the page content that survive the search [q]; whole cards stay
  /// when the page itself matched by title/keywords but no row did.
  List<Widget> _filterPage(List<Widget> page, String q, bool pageMatched) {
    if (q.isEmpty) return page;
    final anyRow = page.any((w) => _widgetMatches(w, q));
    if (!anyRow) return pageMatched ? page : const [];
    return [
      for (final w in page)
        if (w is _SectionLabel)
          w
        else if (w is _SettingsGroupCard)
          if (w.rows.any((r) => _widgetMatches(r, q)))
            _SettingsGroupCard(
                title: w.title,
                rows: [
                  for (final r in w.rows)
                    if (_widgetMatches(r, q) || has(w.title, q)) r,
                ])
          else
            ...const <Widget>[]
        else if (pageMatched)
          w,
    ];
  }

  static bool has(String t, String q) => t.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final (header, groups) = _split();
    final q = _query.toLowerCase();
    final pages = <String, List<Widget>>{};
    final entries = _SettingsScreenState.platformIndex.where((entry) {
      if (!groups.containsKey(entry.id)) return false;
      if (q.isEmpty) {
        pages[entry.id] = groups[entry.id]!;
        return true;
      }
      final pageMatched =
          entry.title.toLowerCase().contains(q) || entry.keywords.contains(q);
      final rows = _filterPage(groups[entry.id]!, q, pageMatched);
      if (rows.isEmpty) return false;
      pages[entry.id] = rows;
      return true;
    }).toList();
    if (entries.isNotEmpty && !entries.any((e) => e.id == _selected)) {
      _selected = entries.first.id;
    }
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
                width: 236,
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
                          // One flat list in the order of the settings map;
                          // search filters it.
                          for (final entry in entries)
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
                            in (pages[_selected] ?? const <Widget>[]).indexed)
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
      w is _NavRow ||
      w is _ToggleRow ||
      w is _ControlRow ||
      w is _PerformanceTile;
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
