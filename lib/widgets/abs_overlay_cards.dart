import 'package:flutter/material.dart';

import '../state/spoken_library_state.dart';
import '../screens/abs/abs_widgets.dart' show absText;
import '../theme/app_theme.dart';

/// The ABS up-next card and the cross-device sync jump banner. Both ride
/// the app's global snackbar (MaterialApp.scaffoldMessengerKey) so they
/// work over every surface — the NPV, the queue sheet, a closed player —
/// without a global overlay, and without knowing anything about the shell.

void showUpNextCard(
  ScaffoldMessengerState? messenger,
  UpNextOffer offer,
  VoidCallback onPlayNow,
  VoidCallback onNotNow,
) {
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor: kRaisedColor,
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      content: Row(children: [
        const Icon(Icons.skip_next_rounded, color: kVioletLight, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Up next — ${offer.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: absText(13, w: FontWeight.w700)),
                Text(offer.episode == null ? offer.fromTitle : offer.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: absText(11, color: kMuted2)),
              ]),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onPlayNow,
          child:
              Text('Play now', style: absText(13, color: kVioletPale, w: FontWeight.w700)),
        ),
        TextButton(
          onPressed: onNotNow,
          child: Text('Not now', style: absText(13, color: kMuted2, w: FontWeight.w600)),
        ),
      ]),
    ));
}

void showSyncNudgeBanner(
  ScaffoldMessengerState? messenger,
  RemoteNudge nudge,
  VoidCallback onJump,
  VoidCallback onDismiss,
) {
  if (messenger == null) return;
  final at = Duration(seconds: nudge.remoteSeconds.round());
  final hh = at.inHours;
  final mm = (at.inMinutes % 60).toString().padLeft(hh > 0 ? 2 : 1, '0');
  final ss = (at.inSeconds % 60).toString().padLeft(2, '0');
  final clock = hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      backgroundColor: kRaisedColor,
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      content: Row(children: [
        const Icon(Icons.devices_rounded, color: kVioletLight, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Updated on another device — jump to $clock?',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: absText(13, w: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onJump,
          child: Text('Jump', style: absText(13, color: kVioletPale, w: FontWeight.w700)),
        ),
        TextButton(
          onPressed: onDismiss,
          child: Text('Dismiss', style: absText(13, color: kMuted2, w: FontWeight.w600)),
        ),
      ]),
    ));
}
