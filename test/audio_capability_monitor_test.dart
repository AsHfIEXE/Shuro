import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/playback/audio_capability.dart';

/// Pins the fix for the stale "Playing from" label (2026-10-18): the monitor
/// must notify listeners when a FRESH answer arrives (that is what repaints
/// Now Playing live on a route change), and must stay silent when it answers
/// from cache — otherwise every diagnostics refresh would flicker the line.
class _FakeSource implements AudioCapabilitySource {
  int reads = 0;

  @override
  Future<AudioCapabilityReport> read({AudioQueryFormat? format}) async {
    reads++;
    return AudioCapabilityReport.unknown;
  }
}

void main() {
  test('monitor notifies on a fresh read, not on a cached one', () async {
    final source = _FakeSource();
    final monitor = AudioCapabilityMonitor(source: source);
    var notifications = 0;
    monitor.addListener(() => notifications++);

    await monitor.refresh();
    expect(source.reads, 1);
    expect(notifications, 1, reason: 'a fresh answer must notify listeners');

    await monitor.refresh(); // cached
    expect(source.reads, 1, reason: 'cached refresh must not hit the source');
    expect(notifications, 1, reason: 'cached refresh must not notify');

    await monitor.recheck();
    expect(source.reads, 2);
    expect(notifications, 2, reason: 'recheck is a fresh answer and must notify');
  });

  test('cached refresh does not re-read or notify after invalidate', () async {
    final source = _FakeSource();
    final monitor = AudioCapabilityMonitor(source: source);
    var notifications = 0;
    monitor.addListener(() => notifications++);

    await monitor.refresh();
    monitor.invalidate(); // route changed: cache dropped
    expect(monitor.last, isNull);
    await monitor.refresh(); // must read again and notify
    expect(source.reads, 2);
    expect(notifications, 2);
  });
}
