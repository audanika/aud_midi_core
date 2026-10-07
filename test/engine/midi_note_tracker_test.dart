// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  late MidiNoteTracker tracker;

  setUp(() => tracker = MidiNoteTracker());

  group('MidiNoteTracker', () {
    group('MidiNoteTracker()', () {
      test('starts without active notes', () {
        expect(tracker.isEmpty, isTrue);
        expect(tracker.groups, isEmpty);
        expect(tracker.notesOf(0), isEmpty);
      });
    });

    group('track(message, {group})', () {
      test('turns notes on and off per group and channel', () {
        tracker
          ..track(const MidiNoteOn(channel: 1, note: 60, velocity: 100))
          ..track(const MidiNoteOn(channel: 0, note: 64, velocity: 90))
          ..track(
            const MidiNoteOn2(channel: 3, note: 40, velocity: 0),
            group: 2,
          )
          ..track(const MidiNoteOn(channel: 1, note: 62, velocity: 1));
        expect(tracker.groups, equals([0, 2]));
        expect(
          tracker.notesOf(0),
          equals([
            (channel: 0, note: 64),
            (channel: 1, note: 60),
            (channel: 1, note: 62),
          ]),
        );
        expect(tracker.notesOf(2), equals([(channel: 3, note: 40)]));

        tracker
          ..track(const MidiNoteOff(channel: 1, note: 60))
          ..track(const MidiNoteOn(channel: 1, note: 62, velocity: 0))
          ..track(const MidiNoteOff2(channel: 3, note: 40), group: 2);
        expect(tracker.notesOf(0), equals([(channel: 0, note: 64)]));
        expect(tracker.groups, equals([0]));
      });

      test('ignores notes off for unknown groups', () {
        tracker.track(const MidiNoteOff(channel: 0, note: 1), group: 5);
        expect(tracker.isEmpty, isTrue);
      });

      for (final controller in [120, 123, 124, 125, 126, 127]) {
        test('turns a channel off with controller $controller', () {
          tracker
            ..track(const MidiNoteOn(channel: 0, note: 60, velocity: 1))
            ..track(const MidiNoteOn(channel: 1, note: 61, velocity: 1))
            ..track(
              MidiControlChange(channel: 0, controller: controller, value: 0),
            );
          expect(tracker.notesOf(0), equals([(channel: 1, note: 61)]));
          tracker.track(
            MidiControlChange2(channel: 1, controller: controller, value: 0),
          );
          expect(tracker.isEmpty, isTrue);
        });
      }

      test('keeps notes for other controllers and messages', () {
        tracker
          ..track(const MidiNoteOn(channel: 0, note: 60, velocity: 1))
          ..track(
            const MidiControlChange(
              channel: 0,
              controller: MidiControllers.resetAllControllers,
              value: 0,
            ),
          )
          ..track(const MidiTimingClock());
        expect(tracker.notesOf(0), equals([(channel: 0, note: 60)]));
      });

      test('turns a group off with System Reset', () {
        tracker
          ..track(const MidiNoteOn(channel: 0, note: 60, velocity: 1))
          ..track(const MidiNoteOn(channel: 0, note: 60, velocity: 1), group: 1)
          ..track(const MidiSystemReset());
        expect(tracker.groups, equals([1]));
      });
    });

    group('clear()', () {
      test('forgets all notes', () {
        tracker
          ..track(const MidiNoteOn(channel: 0, note: 60, velocity: 1))
          ..clear();
        expect(tracker.isEmpty, isTrue);
      });
    });
  });
}
