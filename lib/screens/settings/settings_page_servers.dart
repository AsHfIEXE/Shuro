part of 'settings_screen.dart';

/// Settings -> Servers and sources.
///
/// Functional: connection status, Sync now (library refresh), rename/URL edit
/// and credential change (reconnects through AppState.connectToServer),
/// scrobble per server, streaming quality, remove/sign out, add server,
/// Audiobookshelf connect/refresh/remove.
/// Stored until something reads them: self-signed certificates (HTTP client
/// hook), local files switch (library/sidebar hook), Audiobookshelf libraries
/// to show / progress sync / speed / skip seconds (spoken player + sidebar).
extension _ServersPage on _SettingsScreenState {
  List<Widget> serversSection(BuildContext context, AppState appState) {
    return [
      _SectionLabel('SERVERS AND SOURCES',
          key: _sectionKey('servers'),
          highlighted: _highlighted == 'servers',
          subtitle:
              'Music comes from Navidrome. Books and podcasts come from Audiobookshelf. Add one, both, or change them any time.'),
      if (appState.servers.isEmpty)
        _SettingsGroupCard(
          title: 'YOUR SERVERS',
          rows: [
            _NavRow(
              icon: Icons.dns_rounded,
              label: appState.isLocalOnly
                  ? 'Local files only'
                  : 'No server connected',
              description: 'Connect a Navidrome server to stream its library.',
            ),
            if (appState.isLocalOnly)
              _NavRow(
                icon: Icons.logout_rounded,
                label: 'Exit local-only mode',
                destructive: true,
                onTap: () => _confirmSignOut(context, isLocalOnly: true),
              ),
          ],
        )
      else
        for (final (i, server) in appState.servers.indexed)
          _ServerBlock(
              key: ValueKey('server-block-${server.id}'),
              server: server,
              showTitle: i == 0),
      _BoardCardGroup(
        children: [
          _buttonRow(
            label: 'Add another server',
            description:
                "Keep a second Navidrome for a different library or a friend's.",
            button: 'Add server',
            primary: true,
            onTap: () => Navigator.of(context).push(
                drillDownRoute(const ServerSetupScreen(isAddingAnother: true))),
          ),
        ],
      ),
      _SettingsGroupCard(
        title: 'PROFILE',
        rows: [
          _NavRow(
            icon: Icons.photo_camera_rounded,
            label: 'Profile photo',
            value: appState.userAvatarBytes != null ? 'Set' : 'Default',
            onTap: () => Navigator.of(context)
                .push(drillDownRoute(const AvatarEditorScreen())),
          ),
        ],
      ),
      const _AudiobookshelfBlock(),
      _ExtrasScope(
        builder: (context, extras) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BoardCardGroup(
              title: 'ON THIS DEVICE',
              children: [
                _switchRow(
                  label: 'Local files',
                  description:
                      'Play music stored on this device next to your server library.',
                  value: extras.showLocalFiles,
                  onChanged: (v) =>
                      extras.update(() => extras.showLocalFiles = v),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }
}

({Color color, String label}) _serverStatusFor(
    AppState appState, ServerConfig server) {
  if (!appState.isServerEnabled(server.id)) {
    return (color: kMuted2, label: 'Disabled');
  }
  if (server.id != appState.activeServerId) {
    return (color: kMuted2, label: 'On standby');
  }
  return switch (appState.connectionStatus) {
    ConnectionStatus.connected => (color: kGreen, label: 'Connected'),
    ConnectionStatus.connecting => (color: kVioletLight, label: 'Connecting'),
    ConnectionStatus.unreachable => (
        color: const Color(0xFFFCA5A5),
        label: 'Unreachable'
      ),
    ConnectionStatus.invalidCredentials => (
        color: const Color(0xFFFCA5A5),
        label: 'Sign-in failed'
      ),
    _ => (color: kMuted2, label: 'Standby'),
  };
}

/// One saved server as a board card.
class _ServerBlock extends StatefulWidget {
  final ServerConfig server;
  final bool showTitle;

  const _ServerBlock({super.key, required this.server, required this.showTitle});

  @override
  State<_ServerBlock> createState() => _ServerBlockState();
}

class _ServerBlockState extends State<_ServerBlock> {
  bool _syncing = false;

  ServerConfig get server => widget.server;

  int _countFor(AppState app, Iterable<String> ids) {
    if (server.id != app.activeServerId && !app.isMultiServer) return -1;
    if (!app.isMultiServer) return ids.length;
    return ids.where((id) => MultiServerLibrary.serverIdOf(id) == server.id).length;
  }

  Future<void> _sync(AppState app) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      if (server.id == app.activeServerId) {
        await app.refreshLibrary();
      } else {
        await app.switchServer(server.id);
      }
      if (!mounted) return;
      if (app.connectionStatus == ConnectionStatus.connected) {
        showSuccessSnackBar(context, 'Library is up to date');
      } else {
        showErrorSnackBar(context,
            app.connectionErrorMessage ?? "Couldn't reach that server.");
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _edit(AppState app, {required bool credentials}) async {
    final name = TextEditingController(text: server.name);
    final url = TextEditingController(text: server.url);
    final user = TextEditingController(text: server.username);
    final pass = TextEditingController();
    final field = (TextEditingController c, String hint,
            {bool obscure = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            obscureText: obscure,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: hint,
              labelStyle: const TextStyle(color: kMutedTextColor),
            ),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text(credentials ? 'Change sign-in' : 'Edit server',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!credentials) ...[
                field(name, 'Name'),
                field(url, 'Server URL'),
              ] else ...[
                field(user, 'Username'),
                field(pass, 'New password', obscure: true),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  credentials
                      ? 'Shuro checks the new sign-in against the server before saving it.'
                      : 'Changing the URL reconnects to the server.',
                  style: _rowHelperStyle(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save')),
        ],
      ),
    );
    final newName = name.text.trim();
    final newUrl = url.text.trim();
    final newUser = user.text.trim();
    final newPass = pass.text;
    name.dispose();
    url.dispose();
    user.dispose();
    pass.dispose();
    if (ok != true || !mounted) return;
    if (!credentials) {
      if (newUrl.isNotEmpty && newUrl != server.url) {
        await app.connectToServer(server.copyWith(
            name: newName.isEmpty ? server.name : newName, url: newUrl));
      } else if (newName.isNotEmpty && newName != server.name) {
        app.renameServer(server.id, newName);
      }
    } else {
      if (newUser.isEmpty) return;
      if (newUser == server.username && newPass.isEmpty) return;
      await app.connectToServer(server.copyWith(
          username: newUser,
          password: newPass.isEmpty ? server.password : newPass));
    }
    if (!mounted) return;
    if (app.connectionStatus != ConnectionStatus.connected) {
      showErrorSnackBar(
          context, app.connectionErrorMessage ?? "Couldn't reach that server.");
    }
  }

  Future<void> _remove(AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Sign out of "${server.name}"?',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text(
            "Its cache is cleared from this device. You'll need to enter its credentials again to reconnect.",
            style: GoogleFonts.getFont(currentFontFamily,
                color: kMutedTextColor, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign out',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = server.id;
    app.removeServer(id);
    unawaited(LibraryCache.clear(id));
    if (app.servers.isEmpty && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final status = _serverStatusFor(app, server);
    final isActive = server.id == app.activeServerId;
    final songs = _countFor(app, app.catalogSongs.map((s) => s.id));
    final albums = _countFor(app, app.catalogAlbums.map((a) => a.id));
    final artists = _countFor(app, app.catalogArtists.map((a) => a.id));
    String stat(int n) => n < 0 ? '—' : '$n';
    return _ExtrasScope(
      builder: (context, extras) => _BoardCardGroup(
        title: widget.showTitle ? 'YOUR SERVERS' : null,
        children: _withHairlines([
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: kBrandColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.dns_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(server.name,
                                  style: GoogleFonts.getFont(currentFontFamily,
                                      color: kTextColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              _PillChip(
                                  text: status.label,
                                  color: status.color,
                                  textColor: status.color),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text('${server.url} · Navidrome',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _rowHelperStyle()),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PillButton(
                      label: _syncing || (isActive && app.isSyncingLibrary)
                          ? 'Syncing…'
                          : 'Sync now',
                      icon: Icons.sync_rounded,
                      onTap: _syncing ? null : () => _sync(app),
                    ),
                    _PillButton(
                        label: 'Edit',
                        icon: Icons.edit_rounded,
                        onTap: () => _edit(app, credentials: false)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatTile(value: stat(songs), label: 'Songs'),
                    const SizedBox(width: 10),
                    _StatTile(value: stat(albums), label: 'Albums'),
                    const SizedBox(width: 10),
                    _StatTile(value: stat(artists), label: 'Artists'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Last sync', style: _rowHelperStyle()),
                    const SizedBox(width: 8),
                    Text(
                        isActive ? _relativeTime(app.lastSyncAt) : '—',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          _buttonRow(
            label: 'Sign-in',
            description:
                'Signed in as ${server.username}. Password is stored in the system keychain.',
            button: 'Change',
            onTap: () => _edit(app, credentials: true),
          ),
          _switchRow(
            label: 'Allow self-signed certificate',
            description: 'Only for servers on your own network.',
            value: extras.selfSignedServerIds.contains(server.id),
            onChanged: (v) => extras.setServerSelfSigned(server.id, v),
          ),
          _switchRow(
            label: 'Scrobble to this server',
            description:
                'Report finished tracks so your play counts stay right.',
            value: !app.scrobbleOffServerIds.contains(server.id),
            onChanged: (v) => app.setServerScrobble(server.id, v),
          ),
          _selectRow(
            label: 'Streaming quality',
            description:
                'Original keeps the file untouched. Transcoding saves data.',
            options: [
              for (final q in StreamingQuality.values)
                (q.name, q == StreamingQuality.original
                    ? 'Original, no transcoding'
                    : q.label),
            ],
            value: app.wifiQuality.name,
            onChanged: (id) => app.updateWifiQuality(StreamingQuality.values
                .firstWhere((q) => q.name == id)),
          ),
          _buttonRow(
            label: 'Remove this server',
            description: 'Signs out and clears its cache on this device.',
            button: 'Sign out',
            destructive: true,
            onTap: () => _remove(app),
          ),
        ]),
      ),
    );
  }
}

/// "IF YOU SKIPPED IT DURING SETUP": the Audiobookshelf card.
class _AudiobookshelfBlock extends StatefulWidget {
  const _AudiobookshelfBlock();

  @override
  State<_AudiobookshelfBlock> createState() => _AudiobookshelfBlockState();
}

class _AudiobookshelfBlockState extends State<_AudiobookshelfBlock> {
  void _openSetup() => Navigator.of(context)
      .push(drillDownRoute(const AudiobookshelfSetupScreen()));

  Future<void> _remove(SpokenLibraryState spoken) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Remove Audiobookshelf?',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text(
            'Books and podcasts disappear from the sidebar. Your server is untouched.',
            style: GoogleFonts.getFont(currentFontFamily,
                color: kMutedTextColor, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true) await spoken.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final spoken = context.watch<SpokenLibraryState>();
    final connection = spoken.connection;
    return _ExtrasScope(
      builder: (context, extras) {
        if (connection == null) {
          return _BoardCardGroup(
            title: 'IF YOU SKIPPED IT DURING SETUP',
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Audiobookshelf',
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kTextColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        _PillChip(
                            text: 'Not connected',
                            color: kMuted2,
                            textColor: kMuted2),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                        'Add it to get Books and podcasts in your sidebar, with listening progress synced to your server.',
                        style: _rowHelperStyle()),
                    if (spoken.error != null) ...[
                      const SizedBox(height: 8),
                      Text(spoken.error!,
                          style: _rowHelperStyle()
                              .copyWith(color: const Color(0xFFFCA5A5))),
                    ],
                    const SizedBox(height: 14),
                    _PillButton(
                        label: 'Add Audiobookshelf',
                        primary: true,
                        onTap: _openSetup),
                  ],
                ),
              ),
            ],
          );
        }
        final items = [for (final l in spoken.itemsByLibrary.values) ...l];
        final books = items.where((i) => i.isBook).toList();
        final shows = items.where((i) => !i.isBook).length;
        final authors = {
          for (final b in books)
            if (b.creator.trim().isNotEmpty) b.creator.trim()
        }.length;
        const skipChoices = [
          ('10', '10 s'),
          ('15', '15 s'),
          ('30', '30 s'),
          ('45', '45 s'),
          ('60', '60 s'),
        ];
        return _BoardCardGroup(
          title: 'AUDIOBOOKSHELF',
          children: _withHairlines([
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(connection.name,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kTextColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      _PillChip(
                          text: spoken.error == null
                              ? 'Connected'
                              : 'Needs attention',
                          color: spoken.error == null
                              ? kGreen
                              : const Color(0xFFFCA5A5),
                          textColor: spoken.error == null
                              ? kGreen
                              : const Color(0xFFFCA5A5)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(connection.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _rowHelperStyle()),
                  if (spoken.error != null) ...[
                    const SizedBox(height: 4),
                    Text(spoken.error!,
                        style: _rowHelperStyle()
                            .copyWith(color: const Color(0xFFFCA5A5))),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PillButton(
                        label: spoken.loading ? 'Syncing…' : 'Sync now',
                        icon: Icons.sync_rounded,
                        onTap: spoken.loading ? null : spoken.refresh,
                      ),
                      _PillButton(label: 'Edit', onTap: _openSetup),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatTile(value: '${books.length}', label: 'Books'),
                      const SizedBox(width: 10),
                      _StatTile(value: '$shows', label: 'Podcast shows'),
                      const SizedBox(width: 10),
                      _StatTile(value: '$authors', label: 'Authors'),
                    ],
                  ),
                  if (extras.absSyncProgress) ...[
                    const SizedBox(height: 12),
                    Text('Progress synced',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kGreenLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            _ControlRow(
              label: 'Libraries to show',
              description: 'Audiobooks and Podcasts appear in the sidebar.',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Audiobooks', style: _rowHelperStyle()),
                  const SizedBox(width: 8),
                  _BoardSwitch(
                    value: extras.absShowAudiobooks,
                    label: 'Audiobooks',
                    onChanged: (v) =>
                        extras.update(() => extras.absShowAudiobooks = v),
                  ),
                  const SizedBox(width: 16),
                  Text('Podcasts', style: _rowHelperStyle()),
                  const SizedBox(width: 8),
                  _BoardSwitch(
                    value: extras.absShowPodcasts,
                    label: 'Podcasts',
                    onChanged: (v) =>
                        extras.update(() => extras.absShowPodcasts = v),
                  ),
                ],
              ),
            ),
            _switchRow(
              label: 'Sync listening progress',
              description: 'Keep position and bookmarks in step with the server.',
              value: extras.absSyncProgress,
              onChanged: (v) => extras.update(() => extras.absSyncProgress = v),
            ),
            _selectRow(
              label: 'Default playback speed',
              description: 'Each book remembers its own speed once you change it.',
              options: const [
                ('0.75', '0.75x'),
                ('1.0', '1.0x'),
                ('1.25', '1.25x'),
                ('1.5', '1.5x'),
                ('1.75', '1.75x'),
                ('2.0', '2.0x'),
              ],
              value: extras.absSpeed.toString(),
              onChanged: (v) =>
                  extras.update(() => extras.absSpeed = double.parse(v)),
            ),
            _ControlRow(
              label: 'Skip back and forward',
              description: 'Seconds jumped by the buttons in Now Playing.',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SelectControl(
                    options: skipChoices,
                    value: '${extras.absSkipBackSeconds}',
                    onChanged: (v) => extras
                        .update(() => extras.absSkipBackSeconds = int.parse(v)),
                  ),
                  const SizedBox(width: 8),
                  Text('/', style: _rowHelperStyle()),
                  const SizedBox(width: 8),
                  _SelectControl(
                    options: skipChoices,
                    value: '${extras.absSkipForwardSeconds}',
                    onChanged: (v) => extras.update(
                        () => extras.absSkipForwardSeconds = int.parse(v)),
                  ),
                ],
              ),
            ),
            _buttonRow(
              label: 'Remove Audiobookshelf',
              description: 'Hides Books and podcasts. Your server is untouched.',
              button: 'Remove',
              destructive: true,
              onTap: () => _remove(spoken),
            ),
          ]),
        );
      },
    );
  }
}
