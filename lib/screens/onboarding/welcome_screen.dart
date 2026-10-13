import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_info.dart';
import '../../models/server_config.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/state_views.dart';
import 'server_setup_screen.dart';

/// "01. Onboarding / Setup > Welcome" — first thing shown before a server
/// is connected. Offers a one-tap reconnect for any previously-saved
/// servers instead of only ever asking for fresh credentials.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Mirrors ManageServersScreen's same fix: tapping a saved server used to
  // fire switchServer() and show nothing until it either silently worked or
  // silently didn't. A spinner on the tapped row plus an error snackbar on
  // failure makes a bad saved password or an unreachable server visible.
  String? _connectingId;

  Future<void> _connect(String id) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = id);
    final appState = context.read<AppState>();
    await appState.switchServer(id);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (appState.connectionStatus != ConnectionStatus.connected && context.mounted) {
      showErrorSnackBar(context, appState.connectionErrorMessage ?? "Couldn't reach that server.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = context.watch<AppState>().servers;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        // Scroll-safe instead of Spacer-driven. The old version used two
        // `Spacer`s inside a fixed Column, which overflows on any screen shorter
        // than its content (landscape phone, small tablet, a resized desktop
        // window) — the same class of bug that was reported on Now Playing.
        // `Center` inside a min-height box reproduces the tall-screen centering
        // without an unbounded-height Spacer, and scrolling takes over when the
        // content genuinely doesn't fit.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppLogo(size: 96),
                        const SizedBox(height: 28),
                        Text(kAppName, style: headingFont(color: kTextColor, fontSize: 28, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Text(
                          kAppTagline,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 14, height: 1.5),
                        ),
              if (servers.isNotEmpty) ...[
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Saved servers', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 10),
                for (final server in servers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _connect(server.id),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: kCardColor, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: kBrandGradient)),
                              child: _connectingId == server.id
                                  ? const Padding(
                                      padding: EdgeInsets.all(9),
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.dns_rounded, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(server.name, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(server.url, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 11)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: kMutedTextColor, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).push(drillDownRoute(const ServerSetupScreen())),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBrandColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                            ),
                            child: Text(
                              servers.isEmpty ? 'Connect to Navidrome' : 'Add another server',
                              style: GoogleFonts.getFont(currentFontFamily, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Skipping the server entirely is a first-class path, not a
                        // hidden escape hatch — Shuro still works as a local player
                        // with no Navidrome at all. Kept visually secondary (text
                        // button, not a second filled button) so "connect a server"
                        // stays the obvious primary action for most people.
                        TextButton(
                          onPressed: () => context.read<AppState>().continueWithoutServer(),
                          child: Text(
                            'Continue without a server',
                            style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
