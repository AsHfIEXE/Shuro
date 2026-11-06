import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/server_config.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_loading_indicator.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import 'audiobookshelf_setup_screen.dart';
import 'onboarding_chrome.dart';

/// "Onboarding 2 / Setup" — Server address / Username / Password /
/// Test Connection, with inline Connecting / Connection failed / Invalid
/// credentials / Server unreachable states, restyled to the board.
///
/// Two modes:
///  * [inOnboarding] (from Welcome): step 2 of 5. Connect success shows the
///    green "N songs found" line and continues to step 3 (Audiobookshelf),
///    and "I'll add it later" skips ahead WITHOUT a server — the server
///    step is optional, and skipping lands on step 3, never in the app.
///  * default (Settings → Servers, Home's "Connect a server", the
///    restoring screen): the pre-redesign behaviour is preserved — success
///    plays [ConnectionSuccessScreen], which pops back exactly as before.
class ServerSetupScreen extends StatefulWidget {
  final bool isAddingAnother;
  final bool inOnboarding;
  const ServerSetupScreen(
      {super.key, this.isAddingAnother = false, this.inOnboarding = false});

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

  String get _hostLabel {
    final uri = Uri.tryParse(_urlController.text.trim());
    final host = uri?.host;
    if (host != null && host.isNotEmpty) return host;
    return _urlController.text.trim().replaceFirst(RegExp(r'^https?://'), '');
  }

  Future<void> _connect({bool advance = true}) async {
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
      if (!widget.inOnboarding) {
        pushDrillDownOnce(context,
            ConnectionSuccessScreen(isAddingAnother: widget.isAddingAnother));
        return;
      }
      if (advance) {
        // Hold the green "songs found" line for a beat (the board's state
        // C), then move on to step 3 — the same auto-advance contract the
        // old ConnectionSuccessScreen had, minus the extra screen.
        unawaited(Future<void>.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          pushDrillDownOnce(context, const AudiobookshelfSetupScreen());
        }));
      }
    }
  }

  void _advance() {
    pushDrillDownOnce(context, const AudiobookshelfSetupScreen());
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final status = appState.connectionStatus;
    final errorMessage = appState.connectionErrorMessage;
    final isConnecting = status == ConnectionStatus.connecting;
    final connected = appState.hasServer;
    final failed = status == ConnectionStatus.invalidCredentials ||
        status == ConnectionStatus.unreachable;

    final form = _FormColumn(
      urlController: _urlController,
      userController: _userController,
      passController: _passController,
      nameController: _nameController,
      obscurePassword: _obscurePassword,
      onToggleObscure: () =>
          setState(() => _obscurePassword = !_obscurePassword),
      hostLabel: _hostLabel,
      isConnecting: isConnecting,
      connected: connected,
      failed: failed,
      errorMessage: errorMessage,
      inOnboarding: widget.inOnboarding,
      onTest: isConnecting ? null : () => _connect(advance: false),
      onPrimary: isConnecting
          ? null
          : connected && widget.inOnboarding
              ? _advance
              : () => _connect(advance: true),
      onSkip: widget.inOnboarding ? _advance : null,
    );

    Widget body;
    if (widget.inOnboarding) {
      body = Stack(
        children: [
          const OnboardingBlobs(),
          SafeArea(
            child: Column(
              children: [
                const OnboardingHeader(currentStep: 1),
                Expanded(child: LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: wide ? 1160 : 560),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: form),
                                  const SizedBox(width: 32),
                                  Expanded(
                                      child:
                                          _LibraryPreview(appState: appState)),
                                ],
                              )
                            : form,
                      ),
                    ),
                  );
                })),
              ],
            ),
          ),
        ],
      );
    } else {
      body = Scaffold(
        backgroundColor: kSurfaceColor,
        appBar: AppBar(backgroundColor: kSurfaceColor, elevation: 0),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: form,
              ),
            ),
          ),
        ),
      );
    }
    return body;
  }
}

/// The whole left column of the board: eyebrow, headline, copy, fields,
/// status line, actions and the skip row.
class _FormColumn extends StatelessWidget {
  const _FormColumn({
    required this.urlController,
    required this.userController,
    required this.passController,
    required this.nameController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.hostLabel,
    required this.isConnecting,
    required this.connected,
    required this.failed,
    required this.errorMessage,
    required this.inOnboarding,
    required this.onTest,
    required this.onPrimary,
    required this.onSkip,
  });

  final TextEditingController urlController;
  final TextEditingController userController;
  final TextEditingController passController;
  final TextEditingController nameController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final String hostLabel;
  final bool isConnecting;
  final bool connected;
  final bool failed;
  final String? errorMessage;
  final bool inOnboarding;
  final VoidCallback? onTest;
  final VoidCallback? onPrimary;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final songCount = appState.catalogSongs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (inOnboarding) ...[
          Entrance(
            child: const StepEyebrow(label: 'STEP 2 OF 5 · YOUR MUSIC'),
          ),
          const SizedBox(height: 12),
          Entrance(
            delay: const Duration(milliseconds: 80),
            child: const StepTitle('Connect your Navidrome server'),
          ),
        ] else ...[
          Text('Connect your server',
              style: headingFont(
                  color: kTextColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 140),
          child: Text(
            inOnboarding
                ? 'Works with Navidrome and any OpenSubsonic server. Your password stays on this device.'
                : 'Enter your Navidrome server details below.',
            style: onboardingBody(color: kNavText, fontSize: 16, height: 1.5),
          ),
        ),
        const SizedBox(height: 24),
        if (failed && errorMessage != null) ...[
          Entrance(
            child: _ErrorBanner(
              title: context.read<AppState>().connectionStatus ==
                      ConnectionStatus.unreachable
                  ? 'Server unreachable'
                  : 'Authentication failed',
              message: errorMessage!,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Entrance(
          delay: const Duration(milliseconds: 200),
          child: OnboardingField(
            label: 'Server address',
            controller: urlController,
            hint: 'https://music.example.com',
            leading: Icons.link_rounded,
            keyboardType: TextInputType.url,
            helper: 'Include the port if your server uses one, like :4533.',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Entrance(
                delay: const Duration(milliseconds: 260),
                child: OnboardingField(
                  label: 'Username',
                  controller: userController,
                  hint: 'your-username',
                  leading: Icons.person_outline_rounded,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Entrance(
                delay: const Duration(milliseconds: 320),
                child: OnboardingField(
                  label: 'Password',
                  controller: passController,
                  hint: '••••••••',
                  leading: Icons.lock_outline_rounded,
                  obscure: obscurePassword,
                  trailing: IconButton(
                    iconSize: 18,
                    color: kStatusText,
                    onPressed: onToggleObscure,
                    icon: Icon(obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Entrance(
          delay: const Duration(milliseconds: 360),
          child: OnboardingField(
            label: 'Server name (optional)',
            controller: nameController,
            hint: 'e.g. Home server',
            leading: Icons.dns_rounded,
          ),
        ),
        const SizedBox(height: 24),
        Entrance(
          delay: const Duration(milliseconds: 440),
          child: ConnectionStatusLine(
            phase: isConnecting
                ? StatusPhase.working
                : connected
                    ? StatusPhase.success
                    : failed
                        ? StatusPhase.error
                        : StatusPhase.idle,
            workingText: 'Contacting $hostLabel…',
            successText: connected
                ? 'Connected · OpenSubsonic · $songCount songs found'
                : 'Connected',
            errorText:
                failed ? 'Connection failed — see the details above' : null,
          ),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 500),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              if (inOnboarding) const BackTextButton(),
              SecondaryPill(
                label: 'Test connection',
                icon: Icons.refresh_rounded,
                onPressed: onTest,
              ),
              PrimaryPill(
                label: connected && inOnboarding ? 'Continue' : 'Connect',
                onPressed: onPrimary,
                enabled: !isConnecting,
              ),
            ],
          ),
        ),
        if (inOnboarding && onSkip != null) ...[
          const SizedBox(height: 24),
          Entrance(
            delay: const Duration(milliseconds: 560),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08))),
              ),
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  SecondaryPill(
                    label: "I'll add it later",
                    height: 46,
                    onPressed: onSkip,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Shuro works without a server — you can play files already on this device.',
                      style: onboardingBody(
                          color: kMuted2, fontSize: 13, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (!inOnboarding) ...[
          const SizedBox(height: 32),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: isConnecting
                  ? Column(
                      key: const ValueKey('connecting'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandLoadingIndicator(size: 36),
                        const SizedBox(height: 12),
                        Text('Connecting…',
                            style: onboardingBody(
                                color: kMutedTextColor, fontSize: 13)),
                      ],
                    )
                  : const SizedBox(key: ValueKey('idle')),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ],
    );
  }
}

/// The board's right panel: "Your library" — shimmer skeletons until a
/// server is connected, then the real counts and the gradient mosaic.
class _LibraryPreview extends StatelessWidget {
  const _LibraryPreview({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final connected = appState.hasServer;
    return Entrance(
      delay: const Duration(milliseconds: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [kSecondaryColor, kBrandColor],
                        ),
                      ),
                      child: const Icon(Icons.music_note_rounded,
                          size: 19, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your library',
                              style: onboardingBody(
                                  color: kTextColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              connected
                                  ? 'Live from ${appState.activeServer?.name ?? 'your server'}'
                                  : 'Shown here once connected',
                              style: onboardingBody(
                                  color: kStatusText, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (connected) ...[
                  Row(
                    children: [
                      Expanded(
                          child: _CountCard(
                              value: '${appState.catalogSongs.length}',
                              label: 'Songs')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _CountCard(
                              value: '${appState.catalogAlbums.length}',
                              label: 'Albums')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _CountCard(
                              value: '${appState.catalogArtists.length}',
                              label: 'Artists')),
                    ],
                  ),
                ] else
                  const _SkeletonBars(),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                  children: [
                    for (final colors in kOnboardingArtGradients)
                      GradientTile(
                        colors: colors,
                        radius: 12,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 17, color: kVioletLight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Shuro talks only to your server. Nothing goes through ours.',
                  style:
                      onboardingBody(color: kMuted2, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: headingFont(
                  color: kTextColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: onboardingBody(color: kStatusText, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Loading placeholders with a gentle pulse. The pulse is decorative and
/// stands down under reduced motion (the bars stay, static).
class _SkeletonBars extends StatefulWidget {
  const _SkeletonBars();

  @override
  State<_SkeletonBars> createState() => _SkeletonBarsState();
}

class _SkeletonBarsState extends State<_SkeletonBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widths = [1.0, 0.7, 1.0, 0.55, 0.85];
    Widget bars(double opacity) => Column(
          children: [
            for (final w in widths)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: w,
                  child: Container(
                    height: 14,
                    decoration: ShapeDecoration(
                      color: Colors.white.withValues(alpha: 0.10 * opacity),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ),
          ],
        );
    if (!onboardingMotionEnabled(context)) return bars(1);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => bars(0.55 + 0.45 * _pulse.value),
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
      decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: onboardingBody(
                        color: Colors.redAccent.shade100,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(message,
                    style: onboardingBody(
                        color: Colors.redAccent.shade100,
                        fontSize: 12,
                        height: 1.4)),
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
  State<ConnectionSuccessScreen> createState() =>
      _ConnectionSuccessScreenState();
}

class _ConnectionSuccessScreenState extends State<ConnectionSuccessScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      if (widget.isAddingAnother) {
        Navigator.of(context).pop(); // this screen
        Navigator.of(context)
            .pop(); // server setup form -> back to the switcher
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
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kBrandColor.withValues(alpha: 0.15)),
                child: const Icon(Icons.check_rounded,
                    color: kBrandColor, size: 44),
              ),
            ),
            const SizedBox(height: 22),
            Text('Connected',
                style: headingFont(
                    color: kTextColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text('Loading your library…',
                style: onboardingBody(color: kMutedTextColor, fontSize: 13)),
            const SizedBox(height: 24),
            const BrandLoadingIndicator(size: 32),
          ],
        ),
      ),
    );
  }
}
