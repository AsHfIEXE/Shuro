import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../backend/audiobookshelf_api.dart';
import '../../models/spoken_media.dart';
import '../../state/player_controller.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';

/// Shared text style for the ABS screens (body font from the app theme).
TextStyle absText(double size,
        {Color color = kTextColor,
        FontWeight w = FontWeight.w400,
        double? ls,
        double? h,
        bool tabular = false}) =>
    GoogleFonts.getFont(currentFontFamily,
        fontSize: size,
        color: color,
        fontWeight: w,
        letterSpacing: ls,
        height: h,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null);

TextStyle absHeading(double size, {Color color = kTextColor, double? ls}) =>
    headingFont(fontSize: size, fontWeight: FontWeight.w800, color: color, letterSpacing: ls);

String absClock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String absLength(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Flat, typographic cover: a deterministic muted palette per title, the
/// real cover on top once it loads. No gradients, no stock icon.
class AbsCover extends StatelessWidget {
  const AbsCover(this.item, {super.key, required this.width, this.height, this.radius = 10});
  final SpokenItem item;
  final double width;
  final double? height;
  final double radius;

  static const _palette = [
    (Color(0xFF2B3A67), Color(0xFFC9D3F2)),
    (Color(0xFF6B4A3A), Color(0xFFF2DDCB)),
    (Color(0xFF2F5D50), Color(0xFFCDEBDD)),
    (Color(0xFF5B3A6B), Color(0xFFE6D0F2)),
    (Color(0xFF6B2F3E), Color(0xFFF2CDD6)),
    (Color(0xFF3A5A6B), Color(0xFFCDE3F2)),
  ];

  @override
  Widget build(BuildContext context) {
    final h = height ?? width * 1.5;
    final (bg, fg) = _palette[item.title.hashCode.abs() % _palette.length];
    final url = context.read<SpokenLibraryState>().coverUrlFor(item);
    final pad = width * 0.1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: h,
        color: bg,
        padding: EdgeInsets.all(pad),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: kHairline),
        ),
        child: Stack(fit: StackFit.expand, children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(width: width * 0.14, height: 2, color: fg),
              Text(item.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: absHeading((width * 0.13).clamp(12.0, 34.0).toDouble(), color: fg)
                      .copyWith(height: 1.15)),
              if (width > 110)
                Text(item.creator.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: absText(11, color: fg.withValues(alpha: 0.8), ls: 0.8)),
            ],
          ),
          if (url != null)
            Positioned(
              left: -pad, top: -pad, right: -pad, bottom: -pad,
              child: Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  frameBuilder: (_, child, frame, __) => AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: ShuroMotion.standard,
                      child: child)),
            ),
        ]),
      ),
    );
  }
}

class AbsProgressBar extends StatelessWidget {
  const AbsProgressBar(this.value, {super.key, this.height = 4});
  final double value;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0).toDouble(),
          minHeight: height,
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          valueColor: const AlwaysStoppedAnimation(kBrandColor),
        ),
      );
}

class AbsPrimaryButton extends StatelessWidget {
  const AbsPrimaryButton(this.label, {super.key, required this.onTap, this.icon = Icons.play_arrow_rounded});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 24),
          label: Text(label, style: absText(15, color: Colors.white, w: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: kBrandColor,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            shape: const StadiumBorder(),
          ),
        ),
      );
}

class AbsGhostButton extends StatelessWidget {
  const AbsGhostButton(this.label, {super.key, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20, color: kNavText),
          label: Text(label, style: absText(14, w: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape: const StadiumBorder(),
          ),
        ),
      );
}

class AbsChip extends StatelessWidget {
  const AbsChip(this.label, {super.key, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: ShuroMotion.fast,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? kBrandColor : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? kBrandColor : kHairline),
          ),
          child: Text(label,
              style: absText(14, w: FontWeight.w600, color: selected ? Colors.white : kNavText)),
        ),
      );
}

/// Starts ABS playback; shared by every ABS screen.
class AbsActions {
  static Future<void> play(BuildContext context, SpokenItem item,
      {SpokenEpisode? episode, Duration? startAt, bool queue = false}) async {
    final state = context.read<SpokenLibraryState>();
    final player = context.read<PlayerController>();
    final messenger = ScaffoldMessenger.of(context);
    void toast(String m) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(m, style: absText(13)),
          backgroundColor: kRaisedColor,
          behavior: SnackBarBehavior.floating));
    try {
      final session = await state.openSession(item,
          episode: episode,
          forQueue: queue,
          positionReader: () => player.position,
          songIdReader: () => player.currentSong?.id);
      if (session == null) return toast('Not connected — reconnect Audiobookshelf.');
      if (queue) return toast('Added to queue');
      final at = startAt ?? (session.resumeAt > Duration.zero ? session.resumeAt : null);
      await player.playSong(session.song, queue: session.queue, startAt: at);
      final speed = await state.savedSpeedFor(session.progressId);
      if (speed > 0 && speed != player.playbackSpeed) {
        player.playbackSpeed = speed;
        await player.applyPlaybackTweaksNow();
      }
    } on AudiobookshelfApiException catch (e) {
      toast(e.message);
    } catch (_) {
      toast('Playback failed — the server did not answer.');
    }
  }
}
