import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/server_config.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/state_views.dart';
import '../onboarding/server_setup_screen.dart';

/// Server switcher — lets the user hold several Navidrome servers and pick
/// which one is active, each identified by name rather than a bare URL.
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
    if (appState.connectionStatus != ConnectionStatus.connected && context.mounted) {
      showErrorSnackBar(context, appState.connectionErrorMessage ?? "Couldn't reach that server.");
    }
  }

  Future<void> _rename(BuildContext context, String id, String currentName) async {
    final newName = await promptForRename(context, title: 'Rename server', currentName: currentName, hintText: 'Server name');
    if (newName != null && context.mounted) {
      context.read<AppState>().renameServer(id, newName);
    }
  }

  Future<void> _confirmRemove(BuildContext context, String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Remove "$name"?', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
        content: Text("You'll need to enter its credentials again to reconnect.", style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
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

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(backgroundColor: kSurfaceColor, elevation: 0, title: Text('Servers', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (appState.servers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: EmptyStateView(
                icon: Icons.dns_rounded,
                title: 'No servers connected',
                subtitle: "You're listening from local files only. Connect a Navidrome server to stream its full catalog too.",
              ),
            ),
          for (final server in appState.servers)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: _connectingId == server.id
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kBrandColor),
                    )
                  : Icon(
                      server.id == appState.activeServerId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: server.id == appState.activeServerId ? kBrandColor : kMutedTextColor,
                    ),
              title: Text(server.name, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(server.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
              onTap: () => _connect(appState, server.id),
              trailing: PopupMenuButton<String>(
                color: kCardColor,
                icon: const Icon(Icons.more_vert_rounded, color: kMutedTextColor, size: 20),
                onSelected: (value) {
                  if (value == 'rename') _rename(context, server.id, server.name);
                  if (value == 'remove') _confirmRemove(context, server.id, server.name);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rename', child: Text('Rename', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13))),
                  PopupMenuItem(value: 'remove', child: Text('Remove', style: GoogleFonts.getFont(currentFontFamily, color: Colors.redAccent, fontSize: 13))),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(drillDownRoute(const ServerSetupScreen(isAddingAnother: true))),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: kDividerColor)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(appState.servers.isEmpty ? 'Connect a server' : 'Add another server',
                  style: GoogleFonts.getFont(currentFontFamily, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
