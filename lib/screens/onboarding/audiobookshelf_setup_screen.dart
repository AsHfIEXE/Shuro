import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/spoken_media.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import 'onboarding_chrome.dart';
import 'sound_preset_screen.dart';

/// Step 3 of onboarding (board "Onboarding3") — Audiobookshelf, now or
/// later. Entirely optional: "Add and continue" wires to the exact same
/// `SpokenLibraryState.connect` the Books-and-podcasts screen uses (server
/// URL + API token, token in secure storage), and "I'll add it later" is
/// the default-shaped path onward to step 4.
///
/// Note on the board's username/password tab: Shuro's Audiobookshelf
/// support authenticates with an API token (see `AudiobookshelfApi`), so
/// the form presents the token sign-in only — no password fields that
/// couldn't actually log anyone in.
class AudiobookshelfSetupScreen extends StatefulWidget {
  const AudiobookshelfSetupScreen({super.key});

  @override
  State<AudiobookshelfSetupScreen> createState() =>
      _AudiobookshelfSetupScreenState();
}

class _AudiobookshelfSetupScreenState extends State<AudiobookshelfSetupScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _nameController = TextEditingController(text: 'Audiobookshelf');
  bool _obscureToken = true;

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String get _hostLabel {
    final uri = Uri.tryParse(_urlController.text.trim());
    final host = uri?.host;
    if (host != null && host.isNotEmpty) return host;
    return _urlController.text.trim();
  }

  Future<void> _connect({required bool advance}) async {
    final state = context.read<SpokenLibraryState>();
    await state.connect(
      name: _nameController.text,
      url: _urlController.text,
      token: _tokenController.text,
    );
    if (!mounted) return;
    if (state.connection != null && state.error == null && advance) {
      // Show the green "libraries found" line for a beat, then step 4.
      unawaited(Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        pushDrillDownOnce(context, const SoundPresetScreen());
      }));
    }
  }

  void _advance() => pushDrillDownOnce(context, const SoundPresetScreen());

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SpokenLibraryState>();
    final connected = state.connection != null && state.error == null;
    final busy = state.loading;
    final failed = state.error != null && !connected;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: Stack(
        children: [
          const OnboardingBlobs(),
          SafeArea(
            child: Column(
              children: [
                const OnboardingHeader(currentStep: 2),
                Expanded(child: LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final form = _FormColumn(
                    urlController: _urlController,
                    tokenController: _tokenController,
                    nameController: _nameController,
                    obscureToken: _obscureToken,
                    onToggleObscure: () =>
                        setState(() => _obscureToken = !_obscureToken),
                    hostLabel: _hostLabel,
                    busy: busy,
                    connected: connected,
                    failed: failed,
                    errorText: state.error,
                    onTest: busy ? null : () => _connect(advance: false),
                    onPrimary: busy
                        ? null
                        : connected
                            ? _advance
                            : () => _connect(advance: true),
                    onSkip: _advance,
                  );
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
                                  Expanded(child: _BenefitsPanel(state: state)),
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
      ),
    );
  }
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({
    required this.urlController,
    required this.tokenController,
    required this.nameController,
    required this.obscureToken,
    required this.onToggleObscure,
    required this.hostLabel,
    required this.busy,
    required this.connected,
    required this.failed,
    required this.errorText,
    required this.onTest,
    required this.onPrimary,
    required this.onSkip,
  });

  final TextEditingController urlController;
  final TextEditingController tokenController;
  final TextEditingController nameController;
  final bool obscureToken;
  final VoidCallback onToggleObscure;
  final String hostLabel;
  final bool busy;
  final bool connected;
  final bool failed;
  final String? errorText;
  final VoidCallback? onTest;
  final VoidCallback? onPrimary;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final libraryCount = context.watch<SpokenLibraryState>().libraries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Entrance(
          child: const StepEyebrow(
            label: 'STEP 3 OF 5 · YOUR BOOKS AND PODCASTS',
            badge: 'OPTIONAL',
          ),
        ),
        const SizedBox(height: 12),
        Entrance(
          delay: const Duration(milliseconds: 80),
          child: const StepTitle('Add Audiobookshelf'),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 140),
          child: Text(
            'Listen to audiobooks and podcasts next to your music, with progress '
            'synced to your server. Add it now or any time in Settings.',
            style: onboardingBody(color: kNavText, fontSize: 16, height: 1.5),
          ),
        ),
        const SizedBox(height: 24),
        Entrance(
          delay: const Duration(milliseconds: 200),
          child: OnboardingField(
            label: 'Server address',
            controller: urlController,
            hint: 'https://books.example.com',
            leading: Icons.link_rounded,
            keyboardType: TextInputType.url,
          ),
        ),
        const SizedBox(height: 16),
        Entrance(
          delay: const Duration(milliseconds: 260),
          child: OnboardingField(
            label: 'API token',
            controller: tokenController,
            hint: 'Paste your token',
            leading: Icons.vpn_key_rounded,
            obscure: obscureToken,
            trailing: IconButton(
              iconSize: 18,
              color: kStatusText,
              onPressed: onToggleObscure,
              icon: Icon(obscureToken
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded),
            ),
            helper:
                'Create one in your Audiobookshelf web app under Settings → Users. '
                'Stored in this device\'s secure storage.',
          ),
        ),
        const SizedBox(height: 16),
        Entrance(
          delay: const Duration(milliseconds: 320),
          child: OnboardingField(
            label: 'Connection name (optional)',
            controller: nameController,
            hint: 'Audiobookshelf',
            leading: Icons.bookmark_rounded,
          ),
        ),
        const SizedBox(height: 24),
        Entrance(
          delay: const Duration(milliseconds: 380),
          child: ConnectionStatusLine(
            phase: busy
                ? StatusPhase.working
                : connected
                    ? StatusPhase.success
                    : failed
                        ? StatusPhase.error
                        : StatusPhase.idle,
            workingText: 'Contacting $hostLabel…',
            successText: connected
                ? 'Connected · $libraryCount libraries found'
                : 'Connected',
            errorText: failed ? errorText : null,
          ),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 440),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              const BackTextButton(),
              SecondaryPill(
                label: 'Test connection',
                icon: Icons.refresh_rounded,
                onPressed: onTest,
              ),
              PrimaryPill(
                label: 'Add and continue',
                onPressed: onPrimary,
                enabled: !busy,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Entrance(
          delay: const Duration(milliseconds: 500),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
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
                    "Books and podcasts will wait for you in the sidebar — add the server any time in Settings. Skipping changes nothing about your music.",
                    style: onboardingBody(
                        color: kMuted2, fontSize: 13, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The board's right panel: "What you get" before connecting, and the real
/// libraries once a server is attached.
class _BenefitsPanel extends StatelessWidget {
  const _BenefitsPanel({required this.state});

  final SpokenLibraryState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.connection != null && state.error == null;
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
                        color: const Color(0xFFF59E0B),
                      ),
                      child: const Icon(Icons.menu_book_rounded,
                          size: 19, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('What you get',
                              style: onboardingBody(
                                  color: kTextColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              connected
                                  ? '${state.connection?.name} is connected'
                                  : 'Books and podcasts in the sidebar',
                              style: onboardingBody(
                                  color: kStatusText, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (connected) ...[
                  Text('LIBRARIES TO SHOW',
                      style: onboardingBody(
                          color: kMuted2,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  for (final library in state.libraries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _libraryRow(library),
                    ),
                ] else
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BenefitRow(Icons.sync_rounded,
                          'Progress and bookmarks sync both ways'),
                      _BenefitRow(Icons.menu_book_rounded,
                          'Whole-book timeline; every episode keeps its own progress'),
                      _BenefitRow(Icons.podcasts_rounded,
                          'Podcast episodes, resumed where you stopped'),
                      _BenefitRow(Icons.vpn_key_rounded,
                          'Connects with an API token from your own server'),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 17, color: kVioletLight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Skipping changes nothing about your music. Add it whenever you want.',
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

  Widget _libraryRow(SpokenLibrary library) {
    final items = state.itemsByLibrary[library.id] ?? const [];
    final isBook = library.type == SpokenMediaType.book;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: kBrandColor,
            ),
            child:
                const Icon(Icons.check_rounded, size: 13, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(library.name,
                    style: onboardingBody(
                        color: kTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(
                  isBook ? '${items.length} books' : '${items.length} shows',
                  style: onboardingBody(color: kStatusText, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(isBook ? Icons.menu_book_rounded : Icons.podcasts_rounded,
              size: 20, color: kVioletLight),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: kVioletLight),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: onboardingBody(
                  color: const Color(0xFFC9CEDB), fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
