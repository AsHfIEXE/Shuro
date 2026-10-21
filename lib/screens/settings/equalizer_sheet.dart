import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../services/equalizer_service.dart';
import '../../theme/app_theme.dart';

/// Equalizer sheet: enable/bypass plus one slider per system band.
///
/// Sliders drive Android's own equalizer bands (real DSP before the mixer);
/// values persist per band. On platforms without a system equalizer the sheet
/// says so plainly — no dead controls.
Future<void> showEqualizerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurfaceColor,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => const _EqualizerSheet(),
  );
}

class _EqualizerSheet extends StatefulWidget {
  const _EqualizerSheet();

  @override
  State<_EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<_EqualizerSheet> {
  AndroidEqualizerParameters? _params;
  bool _loading = true;
  Timer? _retry;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // A sheet opened before the first track would otherwise keep the
    // "play something" hint forever: the platform only answers once audio
    // exists. Poll briefly instead of asking the user to reopen.
    _retry = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_params != null) {
        timer.cancel();
        return;
      }
      _attempts++;
      if (_attempts > 15) {
        timer.cancel();
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Android only creates the equalizer once audio has been loaded, so
    // before the first track the platform never answers: don't spin forever.
    final params = await EqualizerService.instance
        .parameters()
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    if (!mounted) return;
    setState(() {
      _params = params;
      _loading = false;
    });
  }

  double get _minDb => _params?.minDecibels ?? -12;
  double get _maxDb => _params?.maxDecibels ?? 12;

  @override
  Widget build(BuildContext context) {
    final service = EqualizerService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final params = _params;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Equalizer',
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (params != null)
                        TextButton(
                          onPressed: service.resetBands,
                          child: Text('Flat',
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kMutedTextColor, fontSize: 12.5)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Android system multi-band equalizer (AudioEffect), applied before the mixer.',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kBrandColor)),
                    )
                  else if (params == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        defaultTargetPlatform == TargetPlatform.android
                            ? 'Android creates the equalizer once a track is loaded. Start playing something, then reopen this sheet.'
                            : 'This platform has no system equalizer. Android devices get real DSP here.',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    )
                  else ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Enabled',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: Colors.white, fontSize: 13.5)),
                      value: service.enabled,
                      activeThumbColor: kBrandColor,
                      onChanged: service.setEnabled,
                    ),
                    if (service.enabled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'While the equalizer is on, audio is processed by Android, so bit-perfect / direct USB output is not in use.',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kMutedTextColor,
                              fontSize: 11.5,
                              height: 1.35),
                        ),
                      ),
                    const SizedBox(height: 4),
                    for (final band in params.bands)
                      _BandSlider(
                        label: _hz(band.centerFrequency),
                        value: service.gainOf(band.index).clamp(_minDb, _maxDb),
                        min: _minDb,
                        max: _maxDb,
                        enabled: service.enabled,
                        onChanged: (v) =>
                            service.setGain(band.index, v, persist: false),
                        onChangeEnd: (_) => service.commit(),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      'Range ${_minDb.toStringAsFixed(0)}…${_maxDb.toStringAsFixed(0)} dB · values persist per band.',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMutedTextColor, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _hz(double hz) => hz >= 1000
      ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz'
      : '${hz.round()} Hz';
}

class _BandSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BandSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: kBrandColor,
              inactiveTrackColor: Colors.white12,
              thumbColor: kBrandColor,
              overlayColor: kBrandColor.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text('${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} dB',
              textAlign: TextAlign.right,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white54, fontSize: 11)),
        ),
      ],
    );
  }
}
