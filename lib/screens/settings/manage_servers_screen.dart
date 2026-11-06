import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/server_config.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/motion.dart' show Entrance;
import '../../widgets/page_transitions.dart';
import '../../widgets/state_views.dart';
import '../onboarding/server_setup_screen.dart';

/// Server switcher — lets the user hold several Navidrome servers and pick
/// which one is active, each identified by name rather than a bare URL.
///
/// Redesigned per the SettingsServers board: one card per server with a live
/// status dot (green connected / red unreachable / grey disabled), a Connect
/// action on each card, and every multi-server behaviour kept: enable
/// toggles, active switching, rename, removal (with the confirm + pop-home
/// when the last server goes).
class ManageServersScreen extends StatefulWidget {
  const ManageServersScreen({super.key});

  @override
  State<ManageServersScreen> createState() => _ManageServersScreenState();
}

class _ManageServersScreenState extends State<ManageServersScreen> {
  // Which server row is actively (re)connecting right now, if any — drives
  // a spinner in place of its radio icon so tapping a saved server gives
  // real feedback instead of silently doing nothing until it either
  // connects or fails.
  String? _connectingId;

  Future<void> _connect(AppState appState, String id) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = id);
    await appState.switchServer(id);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (appState.connectionStatus != ConnectionStatus.connected &&
        context.mounted) {
      showErrorSnackBar(context,
          appState.connectionErrorMessage ?? "Couldn't reach that server.");
    }
  }

  Future<void> _rename(
      BuildContext context, String id, String currentName) async {
    final newName = await promptForRename(context,
        title: 'Rename server',
        currentName: currentName,
        hintText: 'Server name');
    if (newName != null && context.mounted) {
      context.read<AppState>().renameServer(id, newName);
    }
  }

  Future<void> _confirmRemove(
      BuildContext context, String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Remove "$name"?',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text(
            "You'll need to enter its credentials again to reconnect.",
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
    if (confirmed == true && context.mounted) {
      final appState = context.read<AppState>();
      appState.removeServer(id);
      // removeServer() falls back to localOnly (not disconnected) once no
      // servers remain, so the right signal that there's nothing left to
      // manage here is an empty server list, not a connection status that
      // this path never actually produces.
      if (appState.servers.isEmpty && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final canNavigateBack = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  if (canNavigateBack)
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon:
                          const Icon(Icons.arrow_back_rounded, color: kNavText),
                    ),
                  Text(
                    'Servers',
                    style: DesktopTokens.section(GoogleFonts.getFont(
                        currentFontFamily,
                        color: kTextColor,
                        letterSpacing: -0.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Music comes from your Navidrome servers. Add another, switch the active one, or turn a server off any time.',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kStatusText, fontSize: 13, height: 18 / 13),
            ),
            const SizedBox(height: 16),
            if (appState.servers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: EmptyStateView(
                  icon: Icons.dns_rounded,
                  title: 'No servers connected',
                  subtitle:
                      "You're listening from local files only. Connect a Navidrome server to stream its full catalog too.",
                ),
              ),
            if (appState.servers.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: kGlass,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Turn a server on to include its music in one combined library. '
                      'Two or more on = every enabled server\'s catalog, merged with no duplicates. '
                      'One on = that server alone.',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kStatusText, fontSize: 12, height: 16 / 12),
                    ),
                  ),
                ),
              ),
            for (final (i, server) in appState.servers.indexed)
              Entrance(
                key: ValueKey(server.id),
                delay: Entrance.stagger(i),
                child: _ServerCard(
                  server: server,
                  connecting: _connectingId == server.id,
                  status: _serverStatus(appState, server),
                  active: server.id == appState.activeServerId,
                  enabled: appState.isServerEnabled(server.id),
                  // A single server can't be switched off — there would be
                  // nothing left to play from. Same rule as before.
                  onToggleEnabled: appState.servers.length > 1
                      ? (value) => appState.setServerEnabled(server.id, value)
                      : null,
                  onConnect: () => _connect(appState, server.id),
                  onRename: () => _rename(context, server.id, server.name),
                  onRemove: () =>
                      _confirmRemove(context, server.id, server.name),
                ),
              ),
            const SizedBox(height: 8),
            _AddServerButton(
              label: appState.servers.isEmpty
                  ? 'Connect a server'
                  : 'Add another server',
              onTap: () => Navigator.of(context).push(drillDownRoute(
                  const ServerSetupScreen(isAddingAnother: true))),
            ),
          ],
        ),
      ),
    );
  }

  /// Status dot semantics per the SettingsServers board: green connected,
  /// red unreachable / sign-in failed, grey disabled or standing by.
  ({Color color, String label}) _serverStatus(
      AppState appState, ServerConfig server) {
    if (!appState.isServerEnabled(server.id)) {
      return (color: kMuted2, label: 'Disabled');
    }
    if (server.id != appState.activeServerId) {
      return (color: kMuted2, label: 'On standby');
    }
    switch (appState.connectionStatus) {
      case ConnectionStatus.connected:
        return (color: kGreen, label: 'Connected');
      case ConnectionStatus.connecting:
        return (color: kVioletLight, label: 'Connecting');
      case ConnectionStatus.unreachable:
        return (color: const Color(0xFFFCA5A5), label: 'Unreachable');
      case ConnectionStatus.invalidCredentials:
        return (color: const Color(0xFFFCA5A5), label: 'Sign-in failed');
      default:
        return (color: kMuted2, label: 'Standby');
    }
  }
}

/// One server, one card (SettingsServers board): gradient tile, name, live
/// status chip, URL, a Connect action for non-active servers, the combined-
/// library toggle, and the rename/remove menu.
class _ServerCard extends StatelessWidget {
  final ServerConfig server;
  final bool connecting;
  final bool active;
  final bool enabled;
  final ({Color color, String label}) status;
  final ValueChanged<bool>? onToggleEnabled;
  final VoidCallback onConnect;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  const _ServerCard({
    required this.server,
    required this.connecting,
    required this.active,
    required this.enabled,
    required this.status,
    required this.onToggleEnabled,
    required this.onConnect,
    required this.onRename,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: kRaisedColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: tap connects (same interaction as the old row).
            InkWell(
              onTap: connecting ? null : onConnect,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [kSecondaryColor, kBrandColor]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.dns_rounded,
                          size: 22, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  server.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.getFont(currentFontFamily,
                                      color: kTextColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusChip(
                                  color: status.color, label: status.label),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            server.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kStatusText, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (connecting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kBrandColor),
                      )
                    else if (!active)
                      _ConnectPill(onTap: onConnect),
                    PopupMenuButton<String>(
                      color: kCardColor,
                      icon: const Icon(Icons.more_vert_rounded,
                          color: kMuted2, size: 20),
                      onSelected: (value) {
                        if (value == 'rename') onRename();
                        if (value == 'remove') onRemove();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.white, fontSize: 13))),
                        PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.redAccent, fontSize: 13))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.06)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Include in combined library',
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          'Off keeps this server\'s music out of the merged library.',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText,
                              fontSize: 12,
                              height: 16 / 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: enabled,
                    activeThumbColor: kBrandColor,
                    onChanged: onToggleEnabled,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status chip: an 8 px dot plus label (green/red/grey per state).
class _StatusChip extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Board-styled filled action pill ("Connect").
class _ConnectPill extends StatelessWidget {
  final VoidCallback onTap;

  const _ConnectPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kBrandColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('Connect',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// The board's violet "Add server" pill.
class _AddServerButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AddServerButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: kBrandColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
