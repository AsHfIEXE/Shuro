import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/server_config.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_loading_indicator.dart';

import '../../widgets/page_transitions.dart';
/// "01. Onboarding / Setup" — Server name / URL / Username / Password /
/// Test Connection, with inline Connecting / Connection failed / Invalid
/// credentials / Server unreachable states. Also reused from Settings to
/// add an additional server ([isAddingAnother]) — in that case success
/// pops back to the server switcher instead of into the main app.
class ServerSetupScreen extends StatefulWidget {
  final bool isAddingAnother;
  const ServerSetupScreen({super.key, this.isAddingAnother = false});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController(text: 'https://');
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final appState = context.read<AppState>();
    await appState.connectToServer(ServerConfig(
      id: '',
      name: _nameController.text,
      url: _urlController.text,
      username: _userController.text,
      password: _passController.text,
    ));
    if (!mounted) return;
    if (appState.connectionStatus == ConnectionStatus.connected) {
      Navigator.of(context).push(drillDownRoute(ConnectionSuccessScreen(isAddingAnother: widget.isAddingAnother)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AppState>().connectionStatus;
    final errorMessage = context.watch<AppState>().connectionErrorMessage;
    final isConnecting = status == ConnectionStatus.connecting;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(backgroundColor: kSurfaceColor, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connect your server', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Enter your Navidrome server details below.',
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
              const SizedBox(height: 28),
              if (errorMessage != null &&
                  (status == ConnectionStatus.invalidCredentials || status == ConnectionStatus.unreachable)) ...[
                _ErrorBanner(
                  title: status == ConnectionStatus.unreachable ? 'Server unreachable' : 'Authentication failed',
                  message: errorMessage,
                ),
                const SizedBox(height: 20),
              ],
              _FieldLabel('Server name (optional)'),
              _TextField(controller: _nameController, hint: 'e.g. Home server'),
              const SizedBox(height: 18),
              _FieldLabel('Server URL'),
              _TextField(controller: _urlController, hint: 'https://music.example.com', keyboardType: TextInputType.url),
              const SizedBox(height: 18),
              _FieldLabel('Username'),
              _TextField(controller: _userController, hint: 'your-username'),
              const SizedBox(height: 18),
              _FieldLabel('Password'),
              _TextField(
                controller: _passController,
                hint: '••••••••',
                obscure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: kMutedTextColor, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isConnecting ? null : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kBrandColor.withOpacity(0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: isConnecting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text('Connect', style: GoogleFonts.getFont(currentFontFamily, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 40),
              Center(
                child: SizedBox(
                  width: double.infinity,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: isConnecting
                        ? Column(
                            key: const ValueKey('connecting'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const BrandLoadingIndicator(size: 36),
                              const SizedBox(height: 12),
                              Text('Connecting…', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
                            ],
                          )
                        : const SizedBox(key: ValueKey('idle')),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
      );
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;

  const _TextField({required this.controller, required this.hint, this.obscure = false, this.suffix, this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 14),
        filled: true,
        fillColor: kCardColor,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String title;
  final String message;
  const _ErrorBanner({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.getFont(currentFontFamily, color: Colors.redAccent.shade100, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(message, style: GoogleFonts.getFont(currentFontFamily, color: Colors.redAccent.shade100, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Connection Success" — brief confirmation before landing in the app.
/// Navigates itself away once its animation plays out (rather than relying
/// on the caller to await a user action that never comes), so onboarding
/// can never get stuck here.
class ConnectionSuccessScreen extends StatefulWidget {
  final bool isAddingAnother;
  const ConnectionSuccessScreen({super.key, this.isAddingAnother = false});

  @override
  State<ConnectionSuccessScreen> createState() => _ConnectionSuccessScreenState();
}

class _ConnectionSuccessScreenState extends State<ConnectionSuccessScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      if (widget.isAddingAnother) {
        Navigator.of(context).pop(); // this screen
        Navigator.of(context).pop(); // server setup form -> back to the switcher
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(shape: BoxShape.circle, color: kBrandColor.withOpacity(0.15)),
                child: const Icon(Icons.check_rounded, color: kBrandColor, size: 44),
              ),
            ),
            const SizedBox(height: 22),
            Text('Connected', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text('Loading your library…', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
            const SizedBox(height: 24),
            const BrandLoadingIndicator(size: 32),
          ],
        ),
      ),
    );
  }
}
