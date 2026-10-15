import 'dart:convert';

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/app_theme.dart';

/// Basic device/app facts shown in Settings → About and included in the
/// first-launch disclosure. Everything here is ALSO displayed to the user in
/// plain sight — nothing is collected that isn't listed on the consent
/// screen, and nothing leaves the device in v1 (no telemetry endpoint).
class DeviceBasics {
  DeviceBasics._();

  static Map<String, String>? _cached;

  static Future<Map<String, String>> collect() async {
    final cached = _cached;
    if (cached != null) return cached;
    final map = <String, String>{};
    try {
      final info = await PackageInfo.fromPlatform();
      map['App version'] = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    try {
      map['Operating system'] = 'Android ${Platform.operatingSystemVersion}';
    } catch (_) {}
    try {
      map['Locale'] = Platform.localeName;
    } catch (_) {}
    _cached = map;
    return map;
  }

  /// The screen-size part of the fingerprint (needs a BuildContext).
  static Map<String, String> screenParts(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return {
      'Screen': '${size.width.round()} × ${size.height.round()} dp',
    };
  }

  /// Compact one-line-per-entry block for display.
  static List<(String, String)> displayRows(BuildContext context) {
    final rows = <(String, String)>[];
    collect().then((map) {
      for (final entry in map.entries) {
        rows.add((entry.key, entry.value));
      }
    });
    return rows;
  }
}

/// Whether the user accepted the terms — persisted in SharedPreferences by
/// the caller (key shared with app.dart's gate).
const String kTermsAcceptedKey = 'shuro_terms_accepted_v1';

class LegalTexts {
  LegalTexts._();

  static const String appOwner = 'AsHfIEXE';

  static const String terms = '''
Terms of Service — Shuro

Last updated: October 2026 · Owner: AsHfIEXE

1. What Shuro is
Shuro is a music player for your own self-hosted music server (Subsonic /
OpenSubsonic compatible, e.g. Navidrome) and for audio files stored on your
device. Shuro is a player: it does not host, provide, or license any music.

2. Your account, your server, your responsibility
You connect Shuro to servers you own or are authorised to use, with
credentials you enter yourself. You are responsible for keeping those
credentials safe and for complying with the terms of your own server and
music licenses.

3. Licence to you
Shuro is provided for personal, non-commercial use. You may not resell it,
or use it to unlawfully distribute copyrighted content.

4. No warranty
Shuro is provided "as is", without warranty of any kind. Playback quality,
device compatibility and feature availability depend on your devices,
network and servers.

5. Limitation of liability
To the maximum extent permitted by law, the author is not liable for any
damages, data loss or license disputes arising from use of the app or of
the servers you connect it to.

6. Third-party services
Shuro talks to services you configure: your music server(s), LRCLIB (lyrics
lookups) and MusicBrainz (artist information). Those services have their
own terms and privacy practices. Shuro never sends your server credentials
to them.

7. Changes
These terms may change with app updates. Continued use after an update
means you accept the updated terms.

8. Contact
AsHfIEXE — via the project's GitHub repository.
''';

  static const String privacy = '''
Privacy summary — Shuro

Last updated: October 2026 · Owner: AsHfIEXE

What Shuro stores, and where:

• Server connections — server address, username and your password. The
  password is stored in Android's encrypted secure storage (Keystore), not
  in plain text.
• Your library life — favourites, play history, playlists, downloads and
  settings, stored on this device only.
• Playback state — queue and position, so you can resume.
• Basic device facts — app version, Android version, screen size and
  language. Shuro v1 has NO analytics and NO telemetry: these facts are
  displayed to you in Settings → About and are not transmitted anywhere by
  the app itself.

What Shuro sends over the network:

• Playback and library requests to the music servers YOU connect (signed
  with your own credentials).
• Lyrics lookups to LRCLIB (song title/artist only) and artist information
  lookups to MusicBrainz (artist name only) when you use those features.

What Shuro never does:

• No advertising. No third-party analytics SDKs. No tracking.
• No music hosting or downloading from anything but your own server.
• Your server credentials are never sent to LRCLIB, MusicBrainz or any
  third party.

Uninstalling the app removes everything above from the device. Your music
server and its data are never modified by uninstalling.

Contact: AsHfIEXE — via the project's GitHub repository.
''';
}

/// First-launch consent: shows the terms and the privacy summary, and only
/// proceeds once the user agrees. Rendered by AuthGate before everything
/// else on a fresh install.
class ConsentScreen extends StatelessWidget {
  final VoidCallback onAccepted;

  const ConsentScreen({super.key, required this.onAccepted});

  @override
  Widget build(BuildContext context) {
    void showFull(String title, String body) {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: kCardColor,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (sheetContext) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (_, controller) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: controller,
                    child: Text(body, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 13, height: 1.55)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Before you start',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Shuro is a player for the music server you own, and for the '
                    'files on this device. It hosts no music itself.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showFull('Terms of Service', LegalTexts.terms),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: kDividerColor)),
                          icon: const Icon(Icons.gavel_rounded, size: 16),
                          label: const Text('Terms', style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showFull('Privacy summary', LegalTexts.privacy),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: kDividerColor)),
                          icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                          label: const Text('Privacy', style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kCardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kDividerColor),
                    ),
                    child: Text(
                      'On this device, Shuro stores: your server address, username and '
                      'password (password encrypted with Android Keystore); your '
                      'favourites, playlists, history and settings; and basic device '
                      'facts (app version, Android version, screen size, language) that '
                      'you can view any time in Settings → About.\n\n'
                      'No advertising. No analytics. No tracking. Nothing about you is '
                      'sold or shared.',
                      style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: onAccepted,
                    child: Text(
                      'I agree — continue',
                      style: GoogleFonts.getFont(currentFontFamily, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'By continuing you accept the Terms of Service and the Privacy summary above.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white24, fontSize: 10.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small helper for the About screen: the persisted acceptance state, typed.
bool termsAcceptedFromPrefs(String? raw) => raw == 'true';
