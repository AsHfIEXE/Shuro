part of 'settings_screen.dart';

/// The remaining Settings pages (everything except Servers, Playback): the
/// rows are the long-standing ones, re-grouped into the index from the
/// "Settings - map" board. Rows without a backing capability are shown
/// informational (value "Not available yet") with the reason, never faked.
extension _MorePages on _SettingsScreenState {
  List<Widget> audioSection(BuildContext context, AppState appState) {
    return [
      _SectionLabel('AUDIO AND EQ',
          key: _sectionKey('audio'),
          highlighted: _highlighted == 'audio',
          subtitle:
              'Shape what you hear and see exactly what reaches your device. Crossfade and gapless live in Playback.'),
      const _AudioEqBody(),
    ];
  }

  List<Widget> librarySection(BuildContext context, AppState appState) {
    return [
      _SectionLabel('LIBRARY',
          key: _sectionKey('library'),
          highlighted: _highlighted == 'library',
          subtitle: 'Sync, folders, hidden items, sort defaults, genre display.'),
      _SettingsGroupCard(
        title: 'SYNC',
        rows: [
          _buttonRow(
            label: 'Sync now',
            description: appState.hasServer
                ? 'Last synced ${_relativeTime(appState.lastSyncAt)}.'
                : 'Connect a server to sync its library.',
            button: 'Sync',
            primary: true,
            onTap: appState.hasServer
                ? () async {
                    await appState.refreshLibrary();
                    if (context.mounted) {
                      showSuccessSnackBar(context, 'Library synced');
                    }
                  }
                : null,
          ),
          _NavRow(
            icon: Icons.sync_rounded,
            label: 'Rescan server library',
            description: 'Ask Navidrome to look for new files.',
            onTap: () => _rescanServer(context),
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'MAINTENANCE',
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
        ],
      ),
      _SettingsGroupCard(
        title: 'DISPLAY',
        rows: const [
          _NavRow(
            icon: Icons.folder_open_rounded,
            label: 'Library folders',
            description: 'Choosing which folders count is not available yet.',
            value: 'Not available yet',
          ),
          _NavRow(
            icon: Icons.visibility_off_rounded,
            label: 'Hidden items',
            description: 'Hiding albums and artists is not available yet.',
            value: 'Not available yet',
          ),
          _NavRow(
            icon: Icons.sort_rounded,
            label: 'Default sort',
            description: 'Each library tab remembers its own sort for now.',
            value: 'Not available yet',
          ),
          _NavRow(
            icon: Icons.category_rounded,
            label: 'Genre display',
            description: 'Genre names are shown as the server tags them.',
            value: 'Not available yet',
          ),
        ],
      ),
    ];
  }

  List<Widget> lyricsSection(BuildContext context, AppState appState,
      AppearanceSettings appearance) {
    return [
      _SectionLabel('LYRICS',
          key: _sectionKey('lyrics'),
          highlighted: _highlighted == 'lyrics',
          subtitle:
              'Source order, font size, sync offset default, translation.'),
      _SettingsGroupCard(
        title: 'SYNC',
        rows: [
          _ToggleRow(
              label: 'Auto-scroll',
              value: appState.lyricsAutoScroll,
              onChanged: appState.updateLyricsAutoScroll),
          _NavRow(
            icon: Icons.sync_rounded,
            description: 'Default offset applied to every song.',
            label: 'Sync adjustment',
            value: appState.lyricsOffsetMs == 0
                ? 'On time'
                : '${appState.lyricsOffsetMs > 0 ? '+' : ''}${appState.lyricsOffsetMs} ms',
            onTap: () => _adjustLyricsSync(context, appState),
          ),
          _sliderRow(
            label: 'Font size',
            description: 'Size of lyrics on the Lyrics screen.',
            value: appearance.lyricsFontScale,
            min: 0.85,
            max: 1.5,
            divisions: 13,
            format: (v) => '${(v * 100).round()}%',
            onCommit: appearance.setLyricsFontScale,
          ),
        ],
      ),

      _SettingsGroupCard(
        title: 'SOURCES',
        rows: const [
          _NavRow(
            icon: Icons.swap_vert_rounded,
            label: 'Source order',
            description: 'Lyrics sources are tried in a fixed order for now.',
            value: 'Not available yet',
          ),
          _NavRow(
            icon: Icons.translate_rounded,
            label: 'Translation',
            description: 'Translated lyrics are not available yet.',
            value: 'Not available yet',
          ),
        ],
      ),
    ];
  }

  List<Widget> downloadsSection(BuildContext context, AppState appState) {
    return [
      _SectionLabel('DOWNLOADS AND OFFLINE',
          key: _sectionKey('downloads'),
          highlighted: _highlighted == 'downloads',
          subtitle: 'Quality, folder, Wi-Fi only, auto-download favorites.'),
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
          const _NavRow(
            icon: Icons.favorite_border_rounded,
            label: 'Auto-download favorites',
            description: 'Downloading new favorites automatically is not available yet.',
            value: 'Not available yet',
          ),
        ],
      ),
    ];
  }

  List<Widget> appearanceSection(BuildContext context, AppState appState,
      AppearanceSettings appearance) {
    return [
      _SectionLabel('APPEARANCE',
          key: _sectionKey('appearance'),
          highlighted: _highlighted == 'appearance',
          subtitle: 'Theme, accent, font, density, hero banner on or off.'),
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
            icon: Icons.view_carousel_rounded,
            label: 'Home banner',
            value: appearance.homeBanner.label,
            onTap: () => _pickHomeBanner(context, appearance),
          ),
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

      _ExtrasScope(
        builder: (context, extras) => _SettingsGroupCard(
          title: 'LYRICS SOURCES',
          rows: [
            _switchRow(
              label: 'lrc.red',
              description:
                  'Word and syllable timing (karaoke). Checked first among the online sources.',
              value: extras.lyricsUseLrcRed,
              onChanged: (v) => extras.update(() => extras.lyricsUseLrcRed = v),
            ),
            _switchRow(
              label: 'LRCLIB',
              description: 'Synced and plain lyrics, including word-timed files.',
              value: extras.lyricsUseLrclib,
              onChanged: (v) => extras.update(() => extras.lyricsUseLrclib = v),
            ),
            _switchRow(
              label: 'Embedded lyrics',
              description: 'Lyrics stored in the file or provided by your server.',
              value: extras.lyricsUseEmbedded,
              onChanged: (v) =>
                  extras.update(() => extras.lyricsUseEmbedded = v),
            ),
            _switchRow(
              label: 'Prefer embedded lyrics',
              description:
                  'Use the file\'s own lyrics before lrc.red and LRCLIB. Your edits and imported .lrc files always come first.',
              value: extras.lyricsPreferEmbedded,
              onChanged: (v) =>
                  extras.update(() => extras.lyricsPreferEmbedded = v),
            ),
          ],
        ),
      ),

      _SettingsGroupCard(
        title: 'RENDER PRESET',
        rows: const [_PerformanceTile()],
      ),
    ];
  }

  List<Widget> desktopSection(BuildContext context) {
    return [
      _SectionLabel('DESKTOP',
          key: _sectionKey('desktop'),
          highlighted: _highlighted == 'desktop',
          subtitle:
              'Tray, start minimized, global shortcuts, media keys, window behaviour.'),
      _ExtrasScope(
        builder: (context, extras) => _SettingsGroupCard(
          title: 'WINDOW',
          rows: [
            _switchRow(
              label: 'Close to tray',
              description: 'Closing the window keeps Shuro playing in the tray.',
              value: extras.closeToTray,
              onChanged: (v) => extras.update(() => extras.closeToTray = v),
            ),
            _switchRow(
              label: 'Start minimized',
              description: 'Open to the tray instead of showing the window.',
              value: extras.startMinimized,
              onChanged: (v) => extras.update(() => extras.startMinimized = v),
            ),
          ],
        ),
      ),
      _SettingsGroupCard(
        title: 'KEYS',
        rows: const [
          _NavRow(
            icon: Icons.keyboard_rounded,
            label: 'Global shortcuts',
            description: 'System-wide shortcuts are not available yet.',
            value: 'Not available yet',
          ),
          _NavRow(
            icon: Icons.skip_next_rounded,
            label: 'Media keys',
            description: 'Media keys follow the system and cannot be remapped.',
            value: 'System',
          ),
        ],
      ),
    ];
  }

  List<Widget> storageSection(BuildContext context) {
    return [
      _SectionLabel('STORAGE AND CACHE',
          key: _sectionKey('cache'),
          highlighted: _highlighted == 'cache',
          subtitle: 'Cache size, clear cache, image cache, offline usage.'),
      const _CacheSection(),
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

    ];
  }

  List<Widget> integrationsSection(BuildContext context, AppState appState) {
    return [
      _SectionLabel('INTEGRATIONS',
          key: _sectionKey('integrations'),
          highlighted: _highlighted == 'integrations',
          subtitle: 'Last.fm, Discord presence, other links.'),
      _SettingsGroupCard(
        title: 'SCROBBLING AND PRESENCE',
        rows: [
          _NavRow(
            icon: Icons.graphic_eq_rounded,
            label: 'ListenBrainz',
            value: ListenBrainzService.instance.token == null
                ? 'Not linked'
                : 'Linked',
            onTap: () => showListenBrainzSheet(context),
          ),
          const _NavRow(
            icon: Icons.album_rounded,
            label: 'Last.fm',
            description: 'Linking a Last.fm account is not available yet.',
            value: 'Not available yet',
          ),
          if (DiscordRpcService.supported)
            ValueListenableBuilder<bool>(
              valueListenable: DiscordRpcService.toggle,
              builder: (context, on, _) => _ToggleRow(
                label: 'Discord presence',
                value: on,
                onChanged: (v) =>
                    unawaited(DiscordRpcService.setEnabled(v)),
                description:
                    'Shows what you play on Discord while Shuro runs: track, artist, album art and progress. Presence is cleared when Discord is closed or this is off.',
              ),
            )
          else
            const _NavRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Discord presence',
              description:
                  'Showing what you play on Discord is a Windows and Linux feature.',
              value: 'Desktop only',
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
        ],
      ),
    ];
  }

  List<Widget> pulseSection(BuildContext context, AppState appState) {
    return [
      _SectionLabel('SHURO PULSE',
          key: _sectionKey('pulse'),
          highlighted: _highlighted == 'pulse',
          subtitle: 'Taste profile, mix length, reset history.'),
      _SettingsGroupCard(
        title: 'MIXES',
        rows: [
          _selectRow(
            label: 'Mix length',
            description: 'How many tracks a generated Pulse mix holds.',
            options: const [
              ('15', '15 tracks'),
              ('25', '25 tracks'),
              ('40', '40 tracks'),
              ('60', '60 tracks'),
            ],
            value: const {15, 25, 40, 60}.contains(appState.pulseMixLength)
                ? '${appState.pulseMixLength}'
                : '25',
            onChanged: (v) => appState.updatePulseMixLength(int.parse(v)),
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'TASTE PROFILE',
        rows: [
          _NavRow(
            icon: Icons.favorite_rounded,
            label: 'Taste profile',
            description: 'Learned from your plays and More or Less like this.',
            value: '${appState.artistAffinity.length} artists',
          ),
          _buttonRow(
            label: 'Reset taste profile',
            description: 'Forget what Pulse learned. Play history is kept.',
            button: 'Reset',
            destructive: true,
            onTap: () => _confirmClear(
              context,
              title: 'Reset taste profile?',
              message: 'Pulse starts learning your taste again from scratch.',
              onConfirm: () async => appState.resetTasteProfile(),
            ),
          ),
          _buttonRow(
            label: 'Reset listening history',
            description: 'Clears plays and taste signals on this device.',
            button: 'Reset',
            destructive: true,
            onTap: () => _confirmClear(
              context,
              title: 'Reset listening history?',
              message: 'Recently played, play counts and the taste profile are cleared.',
              onConfirm: () async => appState.resetListeningHistory(),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> aboutSection(BuildContext context) {
    return [
      _SectionLabel('ABOUT',
          key: _sectionKey('about'),
          highlighted: _highlighted == 'about',
          subtitle: 'Version, licenses, logs, report a problem, check for updates.'),
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
          const _NavRow(
            icon: Icons.system_update_rounded,
            label: 'Check for updates',
            description: 'Update checks are not built in yet.',
            value: 'Not available yet',
          ),
          _NavRow(
            icon: Icons.public_rounded,
            label: 'Services & data sources',
            onTap: () => _showServiceAttributions(context),
          ),
        ],
      ),
    ];
  }
}
