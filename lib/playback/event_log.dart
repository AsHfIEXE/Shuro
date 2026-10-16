import 'package:flutter/foundation.dart';

/// In-app diagnostic event log — a fixed ring of the last [kMaxEvents]
/// playback/UI events, exported by Settings → About → "Report a problem".
///
/// Privacy rules (performance brief §0.4): entries contain ids, states and
/// timings only — never credentials and never URLs with auth params; the
/// redactor below additionally scrubs any `u=`/`t=`/`s=`/`p=` query
/// fragments in case a raw string ever slips in. Nothing is written to a
/// file or network by this class — export goes only where the user takes it.
class PlaybackEventLog {
  PlaybackEventLog._();

  static final PlaybackEventLog instance = PlaybackEventLog._();

  /// Performance brief §1D: last ~300 events.
  static const int kMaxEvents = 300;

  final List<String> _entries = <String>[];

  /// How many older events fell out of the ring — reported in the export so
  /// the reader knows the window is partial.
  int _dropped = 0;

  /// Copy of the ring for tests/debug tooling.
  List<String> get entries => List.unmodifiable(_entries);

  int get droppedCount => _dropped;

  void add(String kind, [Map<String, Object?> details = const {}]) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final buf = StringBuffer('$ts $kind');
    details.forEach((key, value) {
      buf.write(' $key=$value');
    });
    final line = _redact(buf.toString());
    if (_entries.length >= kMaxEvents) {
      _entries.removeAt(0);
      _dropped++;
    }
    _entries.add(line);
    if (!kReleaseMode) debugPrint('[event] $line');
  }

  static final RegExp _secretParams = RegExp(r'[?&][utsp]=[^&\s]*');

  String _redact(String s) => s.replaceAll(_secretParams, '<redacted>');

  /// Builds the plain-text report the user can copy/share. [device] carries
  /// the DeviceBasics map (model, OS, RAM class, app version) the settings
  /// screen already shows in About — nothing beyond those disclosed facts.
  String exportText({required Map<String, String> device}) {
    final now = DateTime.now();
    final buf = StringBuffer()
      ..writeln('Shuro diagnostics (redacted)')
      ..writeln('generated: $now')
      ..writeln('app: ${device['version'] ?? 'unknown'}')
      ..writeln('device: ${device['model'] ?? '?'} · '
          'Android ${device['osVersion'] ?? '?'} · '
          'RAM ${device['ram'] ?? '?'}')
      ..writeln('events: ${_entries.length} shown, $_dropped dropped (ring of $kMaxEvents)')
      ..writeln('--- last events ---');
    for (final line in _entries) {
      buf.writeln(line);
    }
    return _redact(buf.toString());
  }
}
