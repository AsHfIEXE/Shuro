import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/download_state.dart';
import '../models/song.dart';
import '../playback/audio_capability.dart';
import '../playback/audio_diagnostics.dart';
import '../screens/now_playing/audio_info_sheet.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'artwork_thumb.dart';
import 'click_region.dart';

const _kMuted = Color(0xFF9AA3B5);
const _kPopoverCurve = Cubic(0.2, 0.8, 0.2, 1);

/// Shows a small floating card near [anchorContext] (the control that opened
/// it). Closes on an outside click. 140 ms in, 90 ms out.
Future<void> _showAnchoredPopover(
  BuildContext context,
  BuildContext anchorContext, {
  required double width,
  required WidgetBuilder builder,
}) {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return Future<void>.value();
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final anchor = topLeft & box.size;
  final screen = overlay.size;
  final left = (anchor.center.dx - width / 2).clamp(8.0, screen.width - width - 8);
  // Player bars sit at the bottom edge: open upward from the control.
  final bottom = screen.height - anchor.top + 8;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, _, __) => Stack(
      children: [
        Positioned(
          left: left,
          bottom: bottom,
          width: width,
          child: Material(
            color: kCardColor,
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: builder(dialogContext),
          ),
        ),
      ],
    ),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
          parent: animation,
          curve: _kPopoverCurve,
          reverseCurve: _kPopoverCurve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position:
              Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

TextStyle _t(Color c, double size, [FontWeight? w]) => GoogleFonts.getFont(
    currentFontFamily,
    color: c,
    fontSize: size,
    fontWeight: w,
    height: 1.35);

/// The quality pill that opens the signal path popover when clicked.
class SignalPathChip extends StatelessWidget {
  final Song song;
  final String label;
  const SignalPathChip({super.key, required this.song, required this.label});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchor) => Tooltip(
        message: 'Signal path',
        child: ClickRegion(
          onTap: () => showSignalPathPopover(context, anchor, song),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: kGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(kGreen, 11, FontWeight.w700)
                    .copyWith(letterSpacing: 0.2)),
          ),
        ),
      ),
    );
  }
}

Future<void> showSignalPathPopover(
    BuildContext context, BuildContext anchor, Song song) {
  // A user-initiated read, same as opening the audio info sheet.
  final info = song.audioInfo;
  sharedAudioCapabilityMonitor.setQueryFormat(AudioQueryFormat.forCurrentEngine(
    sampleRateHz: info.hasSampleRate ? info.sampleRateHz : null,
    channelCount: info.channelCount,
  ));
  unawaited(sharedAudioCapabilityMonitor.recheck());
  return _showAnchoredPopover(
    context,
    anchor,
    width: 320,
    builder: (_) => _SignalPathPopover(song: song, parentContext: context),
  );
}

class _SignalPathPopover extends StatelessWidget {
  final Song song;
  final BuildContext parentContext;
  const _SignalPathPopover({required this.song, required this.parentContext});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return ListenableBuilder(
      listenable: sharedAudioCapabilityMonitor,
      builder: (context, _) {
        final resolver = player.diagnosticsResolver;
        final d = resolver != null
            ? resolver(song, player.sourcePolicy, player.processingOptions)
            : AudioDiagnostics.forSong(
                song: song,
                policy: player.sourcePolicy,
                processing: player.processingOptions);
        final p = d.processing;
        final effects = [
          if (p.replayGainEnabled) 'ReplayGain',
          if (p.equalizerEnabled) 'Equalizer',
          if (p.crossfadeEnabled) 'Crossfade',
        ];
        final route = switch (d.route.kind) {
          RouteKind.builtIn => 'Built-in output',
          RouteKind.wired => 'Wired output',
          RouteKind.bluetooth => 'Bluetooth',
          RouteKind.usb => d.route.deviceLabel ?? 'USB audio device',
          RouteKind.other => d.route.deviceLabel ?? 'Other route',
          RouteKind.unknown => 'Not reported by this platform',
        };
        final fileInfo = song.audioInfo;
        Widget row(String k, String v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 92, child: Text(k, style: _t(_kMuted, 12))),
                  Expanded(child: Text(v, style: _t(Colors.white, 12.5))),
                ],
              ),
            );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.timeline_rounded, size: 16, color: kBrandColor),
                const SizedBox(width: 8),
                Text('Signal path', style: _t(Colors.white, 14, FontWeight.w600)),
              ]),
              const SizedBox(height: 10),
              row('Source', fileInfo.nothingReported
                  ? 'Format not reported by the server'
                  : [
                      fileInfo.formatLabel,
                      if (fileInfo.hasBitDepth && fileInfo.hasSampleRate)
                        '${fileInfo.bitDepthLabel} / ${fileInfo.sampleRateLabel}'
                      else if (fileInfo.hasBitrate) '${fileInfo.bitrateKbps} kbps',
                    ].join(' · ')),
              row('Request', d.source.policy.quality.label),
              row('Output', route),
              row('Processing', effects.isEmpty ? 'None applied by Shuro' : effects.join(' · ')),
              const SizedBox(height: 8),
              Text(
                'Shuro reports what the file is and what the platform tells it. '
                'It cannot verify the last stage to your speakers, so this is not a bit-perfect claim.',
                style: _t(_kMuted, 11),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showAudioInfoSheet(parentContext, song);
                  },
                  child: const Text('Full audio info'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Queue button for player bars: click opens the queue, hover (desktop) or
/// long-press peeks at the next three tracks with an "Open queue" action.
class QueuePeekButton extends StatefulWidget {
  final VoidCallback onOpen;
  final Color? color;
  final double iconSize;

  /// Optional custom visual (for example a circle action). Tap opens the
  /// queue; the peek behaves the same.
  final Widget? child;
  const QueuePeekButton(
      {super.key,
      required this.onOpen,
      this.color,
      this.iconSize = 24,
      this.child});

  @override
  State<QueuePeekButton> createState() => _QueuePeekButtonState();
}

class _QueuePeekButtonState extends State<QueuePeekButton> {
  OverlayEntry? _entry;
  Timer? _openTimer;
  Timer? _closeTimer;
  bool _overPanel = false;
  bool _overButton = false;

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), () {
      if (!_overPanel && !_overButton) _hide();
    });
  }

  void _hide() {
    _openTimer?.cancel();
    _entry?.remove();
    _entry = null;
  }

  void _show() {
    if (_entry != null || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;
    final anchor = box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
    const width = 300.0;
    final screen = overlayBox.size;
    final left = (anchor.right - width).clamp(8.0, screen.width - width - 8);
    final bottom = screen.height - anchor.top + 8;
    final player = context.read<PlayerController>();
    _entry = OverlayEntry(
      builder: (entryContext) => Stack(
        children: [
          // Outside click closes (needed for the long-press path on touch).
          Positioned.fill(
            child: ClickRegion(
                behavior: HitTestBehavior.translucent, onTap: _hide),
          ),
          Positioned(
            left: left,
            bottom: bottom,
            width: width,
            child: MouseRegion(
              onEnter: (_) => _overPanel = true,
              onExit: (_) {
                _overPanel = false;
                _scheduleClose();
              },
              child: _QueuePeekPanel(
                player: player,
                onOpen: () {
                  _hide();
                  widget.onOpen();
                },
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _overButton = true;
        _closeTimer?.cancel();
        _openTimer?.cancel();
        _openTimer = Timer(const Duration(milliseconds: 350), _show);
      },
      onExit: (_) {
        _overButton = false;
        _openTimer?.cancel();
        _scheduleClose();
      },
      child: ClickRegion(
        // Long-press peeks; tap opens the queue.
        onLongPress: _show,
        child: widget.child != null
            ? ClickRegion(
                onTap: () {
                  _hide();
                  widget.onOpen();
                },
                child: widget.child,
              )
            : IconButton(
          tooltip: 'Queue',
          onPressed: () {
            _hide();
            widget.onOpen();
          },
          icon: Icon(Icons.queue_music_rounded,
              color: widget.color ?? Colors.white54, size: widget.iconSize),
        ),
      ),
    );
  }
}

class _QueuePeekPanel extends StatelessWidget {
  final PlayerController player;
  final VoidCallback onOpen;
  const _QueuePeekPanel({required this.player, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCardColor,
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      child: ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final q = player.queue;
          final start = player.queueIndex + 1;
          final next = start < q.length
              ? q.sublist(start, (start + 3).clamp(0, q.length))
              : <Song>[];
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NEXT UP',
                    style: _t(_kMuted, 11, FontWeight.w700)
                        .copyWith(letterSpacing: 0.8)),
                const SizedBox(height: 8),
                if (next.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nothing queued after this track.',
                        style: _t(Colors.white70, 12.5)),
                  )
                else
                  for (final s in next)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        ArtworkThumb(
                            gradientColors: s.gradientColors,
                            artwork: s.artwork,
                            size: 36,
                            radius: 6),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _t(Colors.white, 13, FontWeight.w600)),
                              Text(s.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _t(_kMuted, 11.5)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: onOpen, child: const Text('Open queue')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
