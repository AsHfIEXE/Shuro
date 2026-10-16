// Phase 1C — seeded chaos driver for the playback engine.
//
// Fires thousands of random player actions at the REAL PlayerController
// running on a REAL just_audio AudioPlayer, which itself runs on a fake
// platform (test/fakes/fake_just_audio_platform.dart) with controllable
// latency and injectable failures. After every action it asserts the
// invariants from the performance brief §1C. Any failure prints the seed,
// the action index and the recent action trace so it reproduces exactly.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:shuro/models/audio_info.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/state/player_controller.dart';

import 'fakes/fake_just_audio_platform.dart';

Song _song(int i) => Song(
      id: 'song-$i',
      title: 'Chaos Song $i',
      artist: 'Artist ${i % 7}',
      artistId: 'artist-${i % 7}',
      albumId: 'album-${i % 5}',
      duration: Duration(seconds: 120 + i),
      gradientColors: const [Colors.red, Colors.blue],
      audioInfo: const AudioInfo(),
      localFilePath: '/fake/library/song-$i.mp3',
    );

/// Captures unhandled errors from both the test zone and Flutter's handler.
class _ErrorSink {
  final List<String> messages = [];

  bool get isEmpty => messages.isEmpty;

  void add(String where, Object error, StackTrace? stack) {
    if (messages.length < 10) {
      messages.add('$where: $error');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('chaos: seeds 1-3 x 300 actions keep the engine invariants', () async {
    for (final seed in [1, 2, 3]) {
      await _runSeed(seed, 300);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('chaos: long run seed 42 x 2000 actions keeps the invariants',
      () async {
    await _runSeed(42, 2000);
  }, timeout: const Timeout(Duration(minutes: 6)));
}

Future<void> _runSeed(int seed, int actionCount) async {
  final errors = _ErrorSink();
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add('FlutterError', details.exception, details.stack);
    // Still forward so the test framework sees real framework problems once.
    // (Commented forward: during chaos we *expect* some engine-level noise;
    // the invariant checks below decide pass/fail, and the messages list
    // keeps the first ten for the report.)
  };
  final platform = FakeJustAudioPlatform();
  JustAudioPlatform.instance = platform;

  final random = Random(seed);
  final songs = List<Song>.generate(25, _song);
  final controller = PlayerController();
  final trace = <String>[];

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 6));
    await Future<void>.delayed(Duration.zero);
  }

  String describe(Object? action) => action.toString();

  void checkInvariants(int actionIndex, String action) {
    final problems = <String>[];
    final queue = controller.queue;
    final index = controller.queueIndex;
    if (index < 0 || (queue.isNotEmpty && index >= queue.length)) {
      problems.add('queueIndex=$index out of bounds (queue=${queue.length})');
    }
    final pos = controller.position;
    if (pos < Duration.zero) problems.add('negative position $pos');
    final dur = controller.duration;
    if (controller.hasEngineDuration && pos > dur + const Duration(seconds: 2)) {
      problems.add('position $pos exceeds duration $dur');
    }
    if (controller.isPlaying &&
        !controller.isBuffering &&
        !controller.hasEngineDuration) {
      problems.add('isPlaying over silence (no engine duration)');
    }
    final song = controller.currentSong;
    if (song != null && !queue.any((s) => s.id == song.id)) {
      problems.add('current song ${song.id} missing from queue');
    }
    if (problems.isNotEmpty) {
      // ignore: avoid_print
      print('SEED $seed FAILED after action $actionIndex ($action)');
      // ignore: avoid_print
      print('last actions: ${trace.take(8).join(' | ')}');
      // ignore: avoid_print
      print('problems: $problems');
      // ignore: avoid_print
      print('state: song=${song?.id} index=$index playing=${controller.isPlaying} '
          'pos=$pos dur=$dur error=${controller.lastPlaybackError}');
      fail(problems.join('; '));
    }
  }

  try {
    for (var i = 0; i < actionCount; i++) {
      final roll = random.nextInt(100);
      String action = 'noop';
      try {
        if (controller.queue.isEmpty || roll < 14) {
          final queue = List<Song>.of(songs);
          final start = random.nextInt(queue.length);
          action = 'playSong(${queue[start].id})';
          trace.insert(0, action);
          // Occasionally inject a load failure for this play.
          if (random.nextInt(8) == 0) {
            platform.players.values.forEach((p) => p.failNextLoad = true);
            action += ' [fail]';
          }
          await controller.playSong(queue[start], queue: queue);
        } else if (roll < 28) {
          action = 'next()';
          trace.insert(0, action);
          await controller.next();
        } else if (roll < 38) {
          action = 'previous()';
          trace.insert(0, action);
          await controller.previous();
        } else if (roll < 50) {
          final d = controller.duration;
          final target = Duration(
              milliseconds:
                  random.nextInt((d + const Duration(seconds: 30)).inMilliseconds));
          action = 'seekTo($target)';
          trace.insert(0, action);
          await controller.seekTo(target);
        } else if (roll < 60) {
          action = 'togglePlayPause()';
          trace.insert(0, action);
          await controller.togglePlayPause();
        } else if (roll < 68) {
          action = 'toggleShuffle()';
          trace.insert(0, action);
          controller.toggleShuffle();
        } else if (roll < 76) {
          action = 'cycleRepeatMode()';
          trace.insert(0, action);
          controller.cycleRepeatMode();
        } else if (roll < 84) {
          final q = controller.queue;
          if (q.length > 1) {
            final victim = random.nextInt(q.length);
            action = 'removeFromQueue($victim)';
            trace.insert(0, action);
            await controller.removeFromQueue(victim);
          } else {
            action = 'removeFromQueue(skipped)';
            trace.insert(0, action);
          }
        } else if (roll < 88) {
          action = 'clearQueue()';
          trace.insert(0, action);
          controller.clearQueue();
        } else if (roll < 93) {
          action = 'sleepTimer EndOfQueue';
          trace.insert(0, action);
          controller.startSleepTimerEndOfQueue();
        } else if (roll < 96) {
          action = 'cancelSleepTimer';
          trace.insert(0, action);
          controller.cancelSleepTimer();
        } else {
          // Rapid-fire burst: three commands with no awaiting in between —
          // the race window the owner actually hits in daily use.
          final q = controller.queue.isNotEmpty
              ? controller.queue
              : List<Song>.of(songs);
          action = 'burst(play/next/pause)';
          trace.insert(0, action);
          unawaited(controller.playSong(
              q[random.nextInt(q.length)],
              queue: List<Song>.of(q)));
          unawaited(controller.next());
          unawaited(controller.pause());
        }
      } on Exception catch (e) {
        // Commands are allowed to fail (offline file, injected failure) —
        // the app must survive it; that is exactly what we are testing.
        errors.add('command($action)', e, StackTrace.current);
      }
      await settle();
      checkInvariants(i, describe(action));
      if (trace.length > 8) trace.removeLast();
      if (!errors.isEmpty) {
        // ignore: avoid_print
        print('SEED $seed: unhandled errors after action $i: ${errors.messages}');
        fail('unhandled errors surfaced');
      }
    }
    // End state: whatever happened, the controller must still respond.
    await controller.playSong(songs.first, queue: List<Song>.of(songs));
    await settle();
    expect(controller.hasSong || controller.lastPlaybackError != null, isTrue,
        reason: 'controller wedged after seed $seed');
  } finally {
    FlutterError.onError = previousOnError;
    controller.dispose();
    await platform.disposeAllPlayers(DisposeAllPlayersRequest());
  }
}
