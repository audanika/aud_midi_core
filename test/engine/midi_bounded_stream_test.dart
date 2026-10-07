// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_core/src/engine/midi_bounded_stream.dart';
import 'package:test/test.dart';

void main() {
  late List<int> overflows;
  late MidiBoundedStream<int> bounded;
  late List<Object> received;

  // Listens to the stream and records values and the end as 'done'.
  StreamSubscription<int> listen() =>
      bounded.stream.listen(received.add, onDone: () => received.add('done'));

  setUp(() {
    overflows = [];
    received = [];
    bounded = MidiBoundedStream<int>(capacity: 3, onOverflow: overflows.add);
  });

  group('MidiBoundedStream', () {
    group('MidiBoundedStream({capacity, onOverflow})', () {
      test('creates an empty stream', () {
        expect(bounded.capacity, 3);
        expect(bounded.queued, 0);
        expect(bounded.isDone, isFalse);
      });

      test('needs room for one value', () {
        expect(
          () => MidiBoundedStream<int>(capacity: 0, onOverflow: (_) {}),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('addAll(values)', () {
      test('delivers in a microtask, in order', () async {
        listen();
        bounded.addAll([1, 2]);
        expect(received, isEmpty);
        await pumpEventQueue();
        expect(received, equals([1, 2]));
      });

      test('keeps values until the first listener', () async {
        bounded.addAll([1, 2]);
        await pumpEventQueue();
        expect(bounded.queued, 2);
        listen();
        await pumpEventQueue();
        expect(received, equals([1, 2]));
      });

      test('drops the newest values beyond the capacity', () async {
        bounded
          ..addAll([1, 2])
          ..addAll([3, 4, 5])
          ..addAll([6]);
        expect(overflows, equals([2, 1]));
        listen();
        await pumpEventQueue();
        expect(received, equals([1, 2, 3]));
      });

      test('holds values while the subscription is paused', () async {
        final subscription = listen()..pause();
        bounded.addAll([1, 2, 3, 4]);
        await pumpEventQueue();
        expect(received, isEmpty);
        expect(overflows, equals([1]));
        subscription.resume();
        await pumpEventQueue();
        expect(received, equals([1, 2, 3]));
      });

      test('stops when the listener pauses within a value', () async {
        late StreamSubscription<int> subscription;
        subscription = bounded.stream.listen((value) {
          received.add(value);
          if (value == 1) subscription.pause();
        });
        bounded.addAll([1, 2]);
        await pumpEventQueue();
        expect(
          [received, bounded.queued],
          equals([
            [1],
            1,
          ]),
        );
        subscription.resume();
        await pumpEventQueue();
        expect(received, equals([1, 2]));
      });

      test('discards values after the listener cancelled', () async {
        await listen().cancel();
        bounded.addAll([1, 2, 3, 4, 5]);
        await pumpEventQueue();
        expect(bounded.queued, 0);
        expect(overflows, isEmpty);
      });
    });

    group('end()', () {
      test('completes after the queued values', () async {
        listen();
        bounded
          ..addAll([1, 2])
          ..end()
          ..addAll([3]);
        expect(bounded.isDone, isTrue);
        await pumpEventQueue();
        expect(received, equals([1, 2, 'done']));
      });

      test('waits with the queued values for a listener', () async {
        bounded
          ..addAll([1])
          ..end();
        await pumpEventQueue();
        listen();
        await pumpEventQueue();
        expect(received, equals([1, 'done']));
      });

      test('completes an empty stream for a late listener', () async {
        bounded
          ..end()
          ..end();
        await pumpEventQueue();
        listen();
        await pumpEventQueue();
        expect(received, equals(['done']));
      });
    });

    group('close()', () {
      test('discards the queued values and completes', () async {
        listen();
        bounded
          ..addAll([1, 2])
          ..close()
          ..close()
          ..end()
          ..addAll([3]);
        await pumpEventQueue();
        expect(received, equals(['done']));
        expect([bounded.queued, bounded.isDone], equals([0, true]));
      });

      test('completes the stream for a late listener', () async {
        bounded.close();
        await pumpEventQueue();
        listen();
        await pumpEventQueue();
        expect(received, equals(['done']));
      });

      test('stops a delivery round when a value closes the stream', () async {
        bounded.stream.listen((value) {
          received.add(value);
          bounded.close();
        });
        bounded.addAll([1, 2]);
        await pumpEventQueue();
        expect(received, equals([1]));
      });
    });
  });
}
