part of 'settings_screen.dart';

/// Settings -> Audio and EQ.
///
/// Functional today: ReplayGain mode and the untagged fallback (PlaybackPrefs,
/// the player reads them), streaming cap (AppState.wifiQuality/mobileQuality),
/// presets (they set the real ReplayGain/gapless/crossfade settings), the
/// equalizer on Android (EqualizerService, 10 bands mapped onto the device's
/// own bands), AutoEq import, saved presets, A/B slots and per-device profiles
/// (applied while this page is open).
/// Stored until the engine hook exists: ReplayGain pre-amp, auto-headroom,
/// limiter, output mode / sample rate / format / surround passthrough, EQ on
/// desktop and iOS, transcode format and "prefer original on Wi-Fi".

const List<String> _eqBandLabels = [
  '31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'
];

double _bandRatio(double a, double b) => a > b ? a / b : b / a;

/// Pushes the 10-band curve onto Android's system equalizer, mapping each
/// device band to the nearest of the ten centre frequencies.
Future<void> _applyEqToDevice(SettingsExtras e) async {
  final service = EqualizerService.instance;
  if (!service.supported) return;
  try {
    final params = await service.parameters();
    if (params == null) return;
    await service.setEnabled(e.eqOn);
    final gains = e.eqGains;
    for (final band in params.bands) {
      var best = 0;
      var bestRatio = double.infinity;
      for (var i = 0; i < EqImport.bandHz.length; i++) {
        final r = _bandRatio(band.centerFrequency, EqImport.bandHz[i]);
        if (r < bestRatio) {
          bestRatio = r;
          best = i;
        }
      }
      final db = gains[best]
          .clamp(params.minDecibels, params.maxDecibels)
          .toDouble();
      await service.setGain(band.index, db, persist: false);
    }
    await service.commit();
  } catch (_) {}
}

/// Marks the engine preset as Custom after a manual change.
void _audioChange(SettingsExtras e, VoidCallback mutate,
    {bool persist = true}) {
  e.update(() {
    mutate();
    e.enginePreset = 'custom';
  }, persist: persist);
}

double _maxBoost(SettingsExtras e) {
  var m = 0.0;
  for (final g in e.eqGains) {
    if (g > m) m = g;
  }
  return e.eqPreampDb > m && e.eqOn ? e.eqPreampDb : m;
}

String _audioFormatLabel(AudioDiagnostics d) {
  final parts = <String>[];
  final codec = d.source.codec?.trim();
  if (codec != null && codec.isNotEmpty) parts.add(codec.toUpperCase());
  final depth = d.source.bitDepth;
  final rate = d.source.sampleRateHz;
  if (depth != null && rate != null) {
    final r = rate % 1000 == 0
        ? '${rate ~/ 1000}'
        : (rate / 1000).toStringAsFixed(1);
    parts.add('$depth/$r');
  } else if (rate != null) {
    parts.add('${(rate / 1000).toStringAsFixed(1)} kHz');
  }
  return parts.isEmpty ? 'Not reported' : parts.join(' ');
}

class _AudioEqBody extends StatefulWidget {
  const _AudioEqBody();

  @override
  State<_AudioEqBody> createState() => _AudioEqBodyState();
}

class _AudioEqBodyState extends State<_AudioEqBody> {
  String? _lastDevice;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    sharedAudioCapabilityMonitor.refresh();
    sharedAudioCapabilityMonitor.addListener(_onRoute);
  }

  @override
  void dispose() {
    sharedAudioCapabilityMonitor.removeListener(_onRoute);
    super.dispose();
  }

  String get _deviceName =>
      sharedAudioCapabilityMonitor.last?.routeLabel?.trim().isNotEmpty == true
          ? sharedAudioCapabilityMonitor.last!.routeLabel!.trim()
          : 'This device output';

  /// Profile switching: when the output changes and that device has a saved
  /// profile, load its EQ and levels. Runs while Settings is open; the app
  /// level hook (route listener in app.dart) is still to be added.
  void _onRoute() {
    final name = _deviceName;
    if (name == _lastDevice) return;
    final first = _lastDevice == null;
    _lastDevice = name;
    final e = SettingsExtras.instance;
    if (first || !e.profileSwitching) return;
    final p = e.deviceProfiles[name];
    if (p != null) _applyProfile(p);
    if (mounted) setState(() {});
  }

  void _applyProfile(Map<String, dynamic> p) {
    final e = SettingsExtras.instance;
    final prefs = context.read<PlaybackPrefs>();
    final gains = p['gains'];
    e.update(() {
      e.eqOn = p['eqOn'] as bool? ?? e.eqOn;
      e.eqPreampDb = (p['eqPreampDb'] as num?)?.toDouble() ?? e.eqPreampDb;
      e.rgPreampDb = (p['preampDb'] as num?)?.toDouble() ?? e.rgPreampDb;
      e.enginePreset = p['preset'] as String? ?? 'custom';
      e.eqPresetName = p['eqPreset'] as String? ?? e.eqPresetName;
      if (gains is List && gains.length == 10) {
        for (var i = 0; i < 10; i++) {
          e.eqGainsA[i] = (gains[i] as num).toDouble();
        }
        e.eqSlot = 'a';
      }
    });
    final rg = p['rgMode'] as String?;
    if (rg != null) prefs.setReplayGainMode(rg);
    unawaited(_applyEqToDevice(e));
  }

  Map<String, dynamic> _snapshot(SettingsExtras e, PlaybackPrefs prefs) => {
        'preset': e.enginePreset,
        'eqOn': e.eqOn,
        'eqPreampDb': e.eqPreampDb,
        'preampDb': e.rgPreampDb,
        'eqPreset': e.eqPresetName,
        'rgMode': prefs.replayGain ? prefs.replayGainMode : 'off',
        'gains': List<double>.of(e.eqGainsA),
      };

  Future<void> _applyPreset(String id, SettingsExtras e, PlaybackPrefs prefs,
      AppState app) async {
    switch (id) {
      case 'pure':
        await prefs.setReplayGainMode('off');
        await prefs.setCrossfadeSeconds(0);
        e.update(() {
          e.enginePreset = 'pure';
          e.autoHeadroom = false;
          e.limiter = false;
          e.eqOn = false;
          e.rgPreampDb = 0.0;
          e.eqPreampDb = 0.0;
        });
      case 'balanced':
        app.toggleSetting(() => app.gaplessPlayback = true);
        await prefs.setReplayGainMode('album');
        e.update(() {
          e.enginePreset = 'balanced';
          e.autoHeadroom = true;
          e.limiter = true;
          e.eqOn = false;
          e.rgPreampDb = 0.0;
        });
      case 'warm':
        await prefs.setReplayGainMode('album');
        e.update(() {
          e.enginePreset = 'warm';
          e.autoHeadroom = true;
          e.limiter = true;
          e.eqOn = true;
          e.eqSlot = 'a';
          const warm = [3.0, 2.5, 1.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
          for (var i = 0; i < 10; i++) {
            e.eqGainsA[i] = warm[i];
          }
          e.eqPresetName = 'Warm';
        });
      default:
        e.update(() => e.enginePreset = 'custom');
    }
    unawaited(_applyEqToDevice(e));
  }

  Future<void> _importAutoEq(SettingsExtras e) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Import AutoEq',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                minLines: 6,
                maxLines: 10,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  hintText:
                      'Preamp: -6.2 dB\nFilter 1: ON PK Fc 105 Hz Gain -2.3 dB Q 0.70',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                  'Imports accept AutoEq and Equalizer APO text. Unknown filter types are rejected and out-of-range values are clamped with a warning. Nothing in the file is ever run.',
                  style: _rowHelperStyle()),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Import')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final result = EqImport.parse(text);
    if (result.error != null) {
      showErrorSnackBar(context, result.error!);
      return;
    }
    _audioChange(e, () {
      final target = e.eqGains;
      for (var i = 0; i < 10; i++) {
        target[i] = result.gains![i];
      }
      e.eqPreampDb = result.preampDb;
      e.eqOn = true;
      e.eqPresetName = 'AutoEq import';
    });
    unawaited(_applyEqToDevice(e));
    if (!mounted) return;
    if (result.warnings.isNotEmpty) {
      showErrorSnackBar(
          context, 'Imported with ${result.warnings.length} warning(s): '
              '${result.warnings.first}');
    } else {
      showSuccessSnackBar(context, 'EQ imported');
    }
  }

  Future<void> _savePreset(SettingsExtras e) async {
    final controller = TextEditingController(text: e.eqPresetName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Save preset',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.getFont(currentFontFamily,
              color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(labelText: 'Preset name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    e.update(() {
      e.eqPresets[name] = List<double>.of(e.eqGains);
      e.eqPresetName = name;
    });
    if (mounted) showSuccessSnackBar(context, 'Saved "$name"');
  }

  Future<void> _editProfile(String name, SettingsExtras e,
      PlaybackPrefs prefs) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text(name,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text(
            'Save the current EQ and levels to this device profile, load the profile now, or delete it.',
            style: _rowHelperStyle()),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('delete'),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
          if (e.deviceProfiles.containsKey(name))
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('load'),
                child: const Text('Load')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('save'),
              child: const Text('Save current')),
        ],
      ),
    );
    if (action == 'save') {
      e.update(() => e.deviceProfiles[name] = _snapshot(e, prefs));
    } else if (action == 'delete') {
      e.update(() => e.deviceProfiles.remove(name));
    } else if (action == 'load') {
      final p = e.deviceProfiles[name];
      if (p != null) _applyProfile(p);
    }
  }

  String _profileSummary(Map<String, dynamic> p) {
    final preset = switch (p['preset']) {
      'pure' => 'Pure',
      'balanced' => 'Balanced',
      'warm' => 'Warm',
      _ => 'Custom',
    };
    final eq = (p['eqOn'] as bool? ?? false) ? 'EQ on' : 'EQ off';
    final pre = (p['preampDb'] as num?)?.toDouble() ?? 0.0;
    return '$preset · $eq, preamp ${_formatDb(pre)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final prefs = context.watch<PlaybackPrefs>();
    final player = context.watch<PlayerController>();
    return _ExtrasScope(builder: (context, e) {
      return ListenableBuilder(
        listenable: sharedAudioCapabilityMonitor,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _presets(e, prefs, app),
            _output(e),
            _signalPath(e, prefs, player),
            _leveling(e, prefs),
            _equalizer(e),
            _profiles(e, prefs),
            _streaming(app, e),
          ],
        ),
      );
    });
  }

  // --- Presets --------------------------------------------------------------
  Widget _presets(SettingsExtras e, PlaybackPrefs prefs, AppState app) {
    const presets = [
      ('pure', 'Pure', 'Every stage off. Cleanest path.'),
      ('balanced', 'Balanced', 'Gapless, ReplayGain by album, limiter on.'),
      ('warm', 'Warm', 'Gentle low shelf with auto-headroom.'),
      ('custom', 'Custom', 'Your own EQ and levels.'),
    ];
    return _BoardCardGroup(
      title: 'PREVIEW OF NEW AUDIO ENGINE',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (id, title, caption) in presets)
                    _PresetTile(
                      title: title,
                      caption: caption,
                      selected: e.enginePreset == id,
                      onTap: () => _applyPreset(id, e, prefs, app),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                  'A preset sets the controls on this page. ReplayGain, gapless, crossfade and the equalizer on Android take effect now; the other stages are saved for the new engine.',
                  style: _rowHelperStyle()),
            ],
          ),
        ),
      ],
    );
  }

  // --- Output ---------------------------------------------------------------
  Widget _output(SettingsExtras e) {
    const engineReason =
        'Saved for the new audio engine. Shuro plays through the system output today.';
    final desktop = _isDesktopPlatform;
    final rates = <(String, String)>[
      ('match', 'Match file'),
      ('44100', '44.1 kHz'),
      ('48000', '48 kHz'),
      ('96000', '96 kHz'),
      ('192000', '192 kHz'),
    ];
    const formats = <(String, String)>[
      ('auto', 'Auto'),
      ('16', '16-bit'),
      ('24', '24-bit'),
      ('32f', '32-bit float'),
    ];
    return _BoardCardGroup(
      title: 'OUTPUT',
      trailingLabel: _isWindowsPlatform
          ? Text('WINDOWS · WASAPI', style: _capsLabelStyle())
          : null,
      children: _withHairlines([
        _selectRow(
          label: 'Output device',
          description:
              'Your DAC, headphones or speakers. Shuro lists what the system reports.',
          options: [
            ('default', 'System default'),
            if (sharedAudioCapabilityMonitor.last?.routeLabel != null)
              ('current', sharedAudioCapabilityMonitor.last!.routeLabel!),
          ],
          value: 'default',
          onChanged: (_) {},
          enabled: false,
          disabledReason:
              'Choose the device in your system sound settings. Shuro follows the system default.',
        ),
        _segmentedRow(
          label: 'Output mode',
          description:
              'System shares the device and the OS may resample. Match file asks for the file\'s own rate. Exclusive takes the device and silences other apps.',
          options: const [
            ('system', 'System'),
            ('match', 'Match file'),
            ('exclusive', 'Exclusive'),
          ],
          value: e.outputMode,
          enabled: _isWindowsPlatform,
          disabledReason: 'Windows only (WASAPI). Other platforms use the system mixer.',
          onChanged: (v) => _audioChange(e, () => e.outputMode = v),
        ),
        _selectRow(
          label: 'Sample rate',
          description:
              'Match file keeps 44.1, 48, 96 kHz and so on as stored.',
          options: rates,
          value: e.sampleRate,
          enabled: desktop,
          disabledReason: 'Desktop only. $engineReason',
          onChanged: (v) => _audioChange(e, () => e.sampleRate = v),
        ),
        _selectRow(
          label: 'Sample format',
          description: 'Output stays in floating point until the last stage.',
          options: formats,
          value: e.sampleFormat,
          enabled: desktop,
          disabledReason: 'Desktop only. $engineReason',
          onChanged: (v) => _audioChange(e, () => e.sampleFormat = v),
        ),
        _switchRow(
          label: 'Surround passthrough',
          description:
              'Send AC-3 and DTS to a receiver over HDMI or S/PDIF. Off for stereo setups.',
          value: e.surroundPassthrough,
          enabled: desktop,
          disabledReason: 'Desktop only. $engineReason',
          onChanged: (v) => _audioChange(e, () => e.surroundPassthrough = v),
        ),
      ]),
    );
  }

  // --- Signal path ----------------------------------------------------------
  Widget _signalPath(
      SettingsExtras e, PlaybackPrefs prefs, PlayerController player) {
    final song = player.currentSong;
    final d = player.getOutputDiagnostics();
    final rgOn = prefs.replayGain;
    final eqLive = e.eqOn;
    final headroom = eqLive && e.autoHeadroom ? -_maxBoost(e) : 0.0;
    final total = (rgOn ? e.rgPreampDb : 0.0) + (eqLive ? _maxBoost(e) : 0.0) + headroom;
    final volume = (prefs.appVolume * 100).round();
    final gainsOff = !rgOn && !eqLive && e.rgPreampDb == 0.0 && !e.autoHeadroom;
    final cap = d?.capability;
    final deviceConfirmed = cap?.bitPerfectUsbAccepted == true;
    final formatConfirmed = cap?.highResolutionPcmAccepted == true;
    final likely =
        gainsOff && volume == 100 && deviceConfirmed && formatConfirmed;

    final nodes = <(String, String, bool)>[
      ('Source', d == null ? 'Nothing playing' : _audioFormatLabel(d), d != null),
      ('Decode', d?.decoder.outputEncoding ?? 'Not reported', d != null),
      ('ReplayGain', rgOn ? (prefs.replayGainMode == 'track' ? 'Track' : 'Album') : 'Off', rgOn),
      ('Preamp', _formatDb(rgOn ? e.rgPreampDb : 0.0), rgOn && e.rgPreampDb != 0.0),
      ('EQ', eqLive ? '10 bands' : 'Off', eqLive),
      ('Headroom', _formatDb(headroom), headroom != 0.0),
      ('Limiter', total <= 0 ? 'Idle' : (e.limiter ? 'On' : 'Off'), total > 0 && e.limiter),
      ('Volume', '$volume%', volume != 100),
      ('Output', d == null ? 'Route not reported' : _audioRouteLabel(d), d != null),
    ];

    final lines = <(bool, String)>[
      (gainsOff, gainsOff ? 'Every gain stage is off' : 'ReplayGain, EQ, headroom on'),
      (volume == 100, volume == 100 ? 'Volume at 100%' : 'App volume at $volume%'),
      (deviceConfirmed,
          deviceConfirmed ? 'Exclusive or direct output active' : (cap?.reason ?? 'Device path not confirmed')),
      (formatConfirmed,
          formatConfirmed ? 'Sample rate and format match the file' : 'Sample rate and format not confirmed'),
    ];

    return _BoardCardGroup(
      title: 'SIGNAL PATH, LIVE',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.graphic_eq_rounded,
                      size: 16, color: kVioletLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        song == null
                            ? 'Nothing is playing'
                            : 'Now playing: ${song.title}'
                                '${d == null ? '' : ' · ${_audioFormatLabel(d)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _rowTitleStyle()),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, value, active) in nodes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? kBrandColor.withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: active
                                ? kBrandColor.withValues(alpha: 0.4)
                                : kHairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kMuted2,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(value,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kTextColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _PillChip(
                text: likely
                    ? 'Bit-perfect path likely'
                    : 'Bit-perfect path not confirmed',
                color: likely ? kGreen : kMuted2,
                textColor: likely ? kGreenLight : kMuted2,
              ),
              const SizedBox(height: 10),
              for (final (ok, text) in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(ok ? Icons.check_rounded : Icons.remove_rounded,
                          size: 15, color: ok ? kGreenLight : kMuted2),
                      const SizedBox(width: 8),
                      Expanded(child: Text(text, style: _rowHelperStyle())),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                  'Pick the Pure preset to turn every stage off. Shuro only shows "Bit-perfect path likely" when all four are true and your device confirms it.',
                  style: _rowHelperStyle()),
            ],
          ),
        ),
      ],
    );
  }

  String _audioRouteLabel(AudioDiagnostics d) => switch (d.route.kind) {
        RouteKind.builtIn => 'Built-in output',
        RouteKind.wired => 'Wired output',
        RouteKind.bluetooth => 'Bluetooth',
        RouteKind.usb => d.route.deviceLabel ?? 'USB audio device',
        RouteKind.other => d.route.deviceLabel ?? 'Other route',
        RouteKind.unknown => 'Route not reported',
      };

  // --- Leveling -------------------------------------------------------------
  Widget _leveling(SettingsExtras e, PlaybackPrefs prefs) {
    final rgValue = !prefs.replayGain ? 'off' : prefs.replayGainMode;
    return _BoardCardGroup(
      title: 'LEVELING AND HEADROOM',
      children: _withHairlines([
        _segmentedRow(
          label: 'ReplayGain',
          description:
              'Match loudness between tracks or albums, using tags in the file.',
          options: const [('off', 'Off'), ('track', 'Track'), ('album', 'Album')],
          value: rgValue,
          onChanged: (v) {
            prefs.setReplayGainMode(v);
            e.update(() => e.enginePreset = 'custom');
          },
        ),
        _sliderRow(
          label: 'ReplayGain pre-amp',
          description: '−24 to +12 dB in 0.1 dB steps. Applied once, in float.',
          value: e.rgPreampDb,
          min: -24,
          max: 12,
          divisions: 360,
          format: _formatDb,
          onCommit: (v) => _audioChange(
              e, () => e.rgPreampDb = (v * 10).roundToDouble() / 10),
        ),
        _sliderRow(
          label: 'Fallback for untagged files',
          description: 'Used when a file has no ReplayGain tags.',
          value: prefs.untaggedPreampDb,
          min: -12,
          max: 12,
          divisions: 240,
          format: _formatDb,
          onCommit: prefs.setUntaggedPreampDb,
        ),
        _switchRow(
          label: 'Auto-headroom',
          description:
              'Lowers the preamp by your largest EQ boost so peaks do not clip.',
          value: e.autoHeadroom,
          onChanged: (v) => _audioChange(e, () => e.autoHeadroom = v),
        ),
        _switchRow(
          label: 'Limiter',
          description:
              'A safety net at −0.1 dBFS. Shows "Idle" while total gain is 0 dB or below.',
          value: e.limiter,
          onChanged: (v) => _audioChange(e, () => e.limiter = v),
        ),
      ]),
    );
  }

  // --- Equalizer ------------------------------------------------------------
  Widget _equalizer(SettingsExtras e) {
    final supported = EqualizerService.instance.supported;
    final gains = e.eqGains;
    return _BoardCardGroup(
      title: 'EQUALIZER',
      children: _withHairlines([
        _ControlRow(
          label: 'On',
          description: e.eqPresetName.isEmpty
              ? (supported
                  ? 'Applied through the Android system equalizer.'
                  : 'Saved only: this platform has no equalizer in the player yet.')
              : '${e.eqPresetName}${supported ? '' : ' · saved only on this platform'}',
          trailing: _BoardSwitch(
            value: e.eqOn,
            label: 'Equalizer',
            onChanged: (v) {
              _audioChange(e, () => e.eqOn = v);
              unawaited(_applyEqToDevice(e));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (e.eqPresets.isNotEmpty)
                    _SelectControl(
                      options: [for (final n in e.eqPresets.keys) (n, n)],
                      value: e.eqPresets.containsKey(e.eqPresetName)
                          ? e.eqPresetName
                          : e.eqPresets.keys.first,
                      onChanged: (n) {
                        _audioChange(e, () {
                          final saved = e.eqPresets[n];
                          if (saved == null || saved.length != 10) return;
                          final g = e.eqGains;
                          for (var i = 0; i < 10; i++) {
                            g[i] = saved[i];
                          }
                          e.eqPresetName = n;
                        });
                        unawaited(_applyEqToDevice(e));
                      },
                    ),
                  _SegmentedControl(
                    options: const [
                      ('graphic', 'Graphic · 10'),
                      ('parametric', 'Parametric'),
                    ],
                    value: 'graphic',
                    disabledIds: const {'parametric'},
                    onChanged: (_) {},
                  ),
                  _PillButton(
                    label: 'A/B compare · ${e.eqSlot.toUpperCase()}',
                    icon: Icons.compare_arrows_rounded,
                    onTap: () {
                      e.update(() => e.eqSlot = e.eqSlot == 'a' ? 'b' : 'a');
                      unawaited(_applyEqToDevice(e));
                    },
                  ),
                  _PillButton(
                      label: 'Import AutoEq',
                      icon: Icons.file_download_outlined,
                      onTap: () => _importAutoEq(e)),
                  _PillButton(
                      label: 'Save preset',
                      icon: Icons.save_outlined,
                      onTap: () => _savePreset(e)),
                  _PillButton(
                    label: 'Flat',
                    onTap: () {
                      _audioChange(e, () {
                        final g = e.eqGains;
                        for (var i = 0; i < g.length; i++) {
                          g[i] = 0.0;
                        }
                        e.eqPreampDb = 0.0;
                        e.eqPresetName = '';
                      });
                      unawaited(_applyEqToDevice(e));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Slot ${e.eqSlot.toUpperCase()}: A/B flips between two curves so you can compare by ear.',
                  style: _rowHelperStyle()),
              const SizedBox(height: 12),
              // Board: response curve over the 10 bands, +12 .. -12 dB.
              Container(
                height: 150,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _EqCurvePainter(
                        List<double>.of(gains), e.eqOn),
                  ),
                ),
              ),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 10; i++)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                                gains[i] > 0
                                    ? '+${gains[i].toStringAsFixed(1)}'
                                    : gains[i].toStringAsFixed(1),
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: kStatusText, fontSize: 10)),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    activeTrackColor: kBrandColor,
                                    inactiveTrackColor: Colors.white12,
                                    thumbColor: kVioletLight,
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 7),
                                  ),
                                  child: Slider(
                                    min: -12,
                                    max: 12,
                                    divisions: 48,
                                    value: gains[i].clamp(-12.0, 12.0),
                                    onChanged: (v) => _audioChange(
                                        e, () => e.eqGains[i] = v,
                                        persist: false),
                                    onChangeEnd: (v) {
                                      _audioChange(e, () => e.eqGains[i] = v);
                                      unawaited(_applyEqToDevice(e));
                                    },
                                  ),
                                ),
                              ),
                            ),
                            Text(_eqBandLabels[i],
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: kMuted2, fontSize: 11)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                  'Imports accept AutoEq and Equalizer APO text. Unknown filter types are rejected and out-of-range values are clamped with a warning. Nothing in the file is ever run.',
                  style: _rowHelperStyle()),
            ],
          ),
        ),
      ]),
    );
  }

  // --- Profiles -------------------------------------------------------------
  Widget _profiles(SettingsExtras e, PlaybackPrefs prefs) {
    final current = _deviceName;
    final names = <String>[
      current,
      for (final n in e.deviceProfiles.keys)
        if (n != current) n,
    ];
    return _BoardCardGroup(
      title: 'PER-DEVICE PROFILES',
      children: _withHairlines([
        _switchRow(
          label: 'Switch profile when the output changes',
          description:
              'Headphones, speakers and your DAC can each keep their own EQ and levels.',
          value: e.profileSwitching,
          onChanged: (v) => e.update(() => e.profileSwitching = v),
        ),
        for (final name in names)
          _ControlRow(
            label: name,
            description: e.deviceProfiles[name] == null
                ? 'No profile saved yet. Edit to save the current settings.'
                : _profileSummary(e.deviceProfiles[name]!),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name == current) ...[
                  _PillChip(text: 'Active', color: kGreen, textColor: kGreenLight),
                  const SizedBox(width: 8),
                ],
                _PillButton(
                    label: 'Edit', onTap: () => _editProfile(name, e, prefs)),
              ],
            ),
          ),
      ]),
    );
  }

  // --- Streaming ------------------------------------------------------------
  Widget _streaming(AppState app, SettingsExtras e) {
    List<(String, String)> caps() => [
          for (final q in StreamingQuality.values)
            (q.name,
                q == StreamingQuality.original ? 'Original (no limit)' : q.label),
        ];
    StreamingQuality byName(String id) =>
        StreamingQuality.values.firstWhere((q) => q.name == id);
    return _BoardCardGroup(
      title: 'STREAMING FROM NAVIDROME',
      children: _withHairlines([
        _selectRow(
          label: 'Maximum bitrate',
          description:
              'Original sends the file as stored. Lower caps use the server to transcode.',
          options: caps(),
          value: app.wifiQuality.name,
          onChanged: (id) {
            app.updateWifiQuality(byName(id));
            if (!e.mobileCapDifferent) app.updateMobileQuality(byName(id));
          },
        ),
        _selectRow(
          label: 'Transcode format',
          description: 'Used only when a cap is set and the server supports it.',
          options: const [
            ('', 'Server default'),
            ('opus', 'Opus'),
            ('mp3', 'MP3'),
            ('aac', 'AAC'),
            ('flac', 'FLAC'),
          ],
          value: app.transcodeFormat,
          onChanged: (v) => app.updateTranscodeFormat(v),
        ),
        _switchRow(
          label: 'Different cap on mobile data',
          description: 'Save data away from Wi-Fi.',
          value: e.mobileCapDifferent,
          onChanged: (v) {
            e.update(() => e.mobileCapDifferent = v);
            if (!v) app.updateMobileQuality(app.wifiQuality);
          },
        ),
        if (e.mobileCapDifferent)
          _selectRow(
            label: 'Mobile data cap',
            description: 'Applies when the connection is not Wi-Fi.',
            options: caps(),
            value: app.mobileQuality.name,
            onChanged: (id) => app.updateMobileQuality(byName(id)),
          ),
        _switchRow(
          label: 'Prefer original on Wi-Fi',
          description:
              'Always request the untouched file on trusted networks.',
          value: app.preferOriginalOnWifi,
          onChanged: (v) => app.updatePreferOriginalOnWifi(v),
        ),
      ]),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final String title;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  const _PresetTile({
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClickRegion(
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: title,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? kBrandColor.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected
                    ? kBrandColor.withValues(alpha: 0.6)
                    : kHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: selected ? kVioletLight : kTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(caption,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 12, height: 16 / 12)),
            ],
          ),
        ),
      ),
    );
  }
}


/// Smooth response curve through the band gains with a violet fill, dB
/// gridlines at +12 / +6 / 0 / -6 / -12 and the band frequencies underneath.
class _EqCurvePainter extends CustomPainter {
  _EqCurvePainter(this.gains, this.on);
  final List<double> gains;
  final bool on;

  static const _freqs = [
    '31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0, right = 12.0, top = 12.0, bottom = 20.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    double yOf(double db) => top + h * (1 - (db.clamp(-12.0, 12.0) + 12) / 24);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (final db in const [12, 6, 0, -6, -12]) {
      final y = yOf(db.toDouble());
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: db > 0 ? '+$db' : '$db',
          style: const TextStyle(color: Color(0xFF6F7890), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 4, y - tp.height / 2));
    }
    if (gains.length < 2) return;
    final n = gains.length;
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(left + w * i / (n - 1), yOf(on ? gains[i] : 0)),
    ];
    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: i < _freqs.length ? _freqs[i] : '',
          style: const TextStyle(color: Color(0xFF6F7890), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(pts[i].dx - tp.width / 2, size.height - bottom + 5));
    }
    // Catmull-Rom -> cubic Bezier.
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < n - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < n ? pts[i + 2] : p2;
      line.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, yOf(-12))
      ..lineTo(pts.first.dx, yOf(-12))
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF7C3AED).withValues(alpha: on ? 0.35 : 0.12),
            const Color(0xFF7C3AED).withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = on ? const Color(0xFFA78BFA) : Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_EqCurvePainter old) =>
      old.on != on || !listEquals(old.gains, gains);
}
