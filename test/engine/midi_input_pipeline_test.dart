// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_core/src/engine/midi_input_pipeline.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  const byteId = MidiPortId('fake:in');
  const umpId = MidiPortId('fake:ump');
  late MidiFakeClock clock;
  late List<MidiDiagnostic> diagnostics;
  late int emptied;

  // A byte input port mapped to [group].
  MidiPortInfo bytePort({int group = 0}) => MidiPortInfo(
    id: byteId,
    name: 'in',
    direction: MidiDirection.input,
    group: group,
  );

  // A UMP input port of [protocol].
  MidiPortInfo umpPort({MidiProtocol protocol = MidiProtocol.midi2}) =>
      MidiPortInfo(
        id: umpId,
        name: 'ump',
        direction: MidiDirection.input,
        protocol: protocol,
        capabilities: const MidiPortCapabilities(ump: true),
      );

  // Returns a pipeline of [port] that records diagnostics and empty calls.
  MidiInputPipeline pipelineOf(MidiPortInfo port) => MidiInputPipeline(
    port: port,
    clock: clock,
    onDiagnostic: diagnostics.add,
    onEmpty: () async => emptied++,
  );

  // A bytes packet of [hex] received at [micros].
  MidiPacket bytes(String hex, [int micros = 0]) =>
      MidiBytesPacket(bytes: MidiBytes.fromHex(hex), time: MidiTime(micros));

  // A UMP packet of [messages] on [group] received at [micros].
  MidiPacket ump(List<MidiMessage> messages, {int group = 0, int micros = 0}) =>
      MidiUmpPacket(
        words: [
          for (final message in messages)
            for (final packet in message.toUmp(group: group)) ...packet.words,
        ],
        time: MidiTime(micros),
      );

  // The kinds of the diagnostics so far.
  List<MidiDiagnosticKind> kinds() => [
    for (final diagnostic in diagnostics) diagnostic.kind,
  ];

  setUp(() {
    clock = MidiFakeClock(start: const MidiTime(77));
    diagnostics = [];
    emptied = 0;
  });

  group('MidiInputPipeline', () {
    group('open(options)', () {
      test('returns an open session of the port', () {
        final pipeline = pipelineOf(bytePort());
        expect(pipeline.isEmpty, isTrue);
        const options = MidiInputOptions(queueCapacity: 9);
        final session = pipeline.open(options);
        expect(session.port, bytePort());
        expect(session.options, options);
        expect(session.isClosed, isFalse);
        expect(pipeline.isEmpty, isFalse);
        expect(pipeline.port, bytePort());
        expect(pipeline.clock, same(clock));
      });
    });

    group('receive(packet)', () {
      test('parses bytes into events on the port group', () async {
        final pipeline = pipelineOf(bytePort(group: 3));
        final events = pipeline.open(const MidiInputOptions()).events.toList();
        pipeline
          ..receive(bytes('90 3c 64 3e 50', 10))
          ..receive(bytes('c1 05', 20))
          ..end();
        expect(
          await events,
          equals([
            const MidiEvent(
              message: MidiNoteOn(channel: 0, note: 60, velocity: 100),
              time: MidiTime(10),
              port: byteId,
              group: 3,
            ),
            const MidiEvent(
              message: MidiNoteOn(channel: 0, note: 62, velocity: 80),
              time: MidiTime(10),
              port: byteId,
              group: 3,
            ),
            const MidiEvent(
              message: MidiProgramChange(channel: 1, program: 5),
              time: MidiTime(20),
              port: byteId,
              group: 3,
            ),
          ]),
        );
      });

      test('reassembles System Exclusive around real-time bytes', () async {
        final pipeline = pipelineOf(bytePort());
        final events = pipeline.open(const MidiInputOptions()).events.toList();
        pipeline
          ..receive(bytes('f0 7e 01', 1))
          ..receive(bytes('f8', 2))
          ..receive(bytes('02 f7', 3))
          ..end();
        expect(
          [for (final event in await events) (event.message, event.time)],
          equals([
            (const MidiTimingClock(), const MidiTime(2)),
            (MidiSysEx([0x7e, 0x01, 0x02]), const MidiTime(1)),
          ]),
        );
      });

      test('decodes UMP with groups', () async {
        final pipeline = pipelineOf(umpPort());
        final events = pipeline.open(const MidiInputOptions()).events.toList();
        const note = MidiNoteOn2(channel: 2, note: 60, velocity: 0x8000);
        const discovery = MidiEndpointDiscovery(requestEndpointInfo: true);
        pipeline
          ..receive(ump([note], group: 5, micros: 4))
          ..receive(ump([discovery], micros: 5))
          ..end();
        expect(
          await events,
          equals([
            const MidiEvent(
              message: note,
              time: MidiTime(4),
              port: umpId,
              group: 5,
            ),
            const MidiEvent(message: discovery, time: MidiTime(5), port: umpId),
          ]),
        );
      });

      test('takes JR timestamps as sender time of later events', () async {
        final pipeline = pipelineOf(umpPort());
        final events = pipeline.open(const MidiInputOptions()).events.toList();
        const on = MidiNoteOn2(channel: 0, note: 60, velocity: 1);
        const off = MidiNoteOff2(channel: 0, note: 60);
        pipeline
          ..receive(ump([const MidiNoop(), on]))
          ..receive(ump([const MidiJrTimestamp(time: 100), on]))
          ..receive(ump([const MidiJrClock(time: 5)]))
          ..receive(ump([off]))
          ..receive(ump([const MidiJrTimestamp(time: 200), off]))
          ..reset()
          ..receive(ump([on]))
          ..end();
        expect([
          for (final event in await events) event.senderTime,
        ], equals([null, 100, 100, 200, null]));
      });

      test('passes raw packets on as received', () async {
        final pipeline = pipelineOf(bytePort());
        final packets = pipeline
            .open(const MidiInputOptions())
            .packets
            .toList();
        final packet = bytes('3c', 1);
        pipeline
          ..receive(packet)
          ..end();
        expect(await packets, equals([packet]));
        expect(kinds(), isEmpty);
      });

      test('collects a stream only from its first read on', () async {
        final pipeline = pipelineOf(bytePort());
        final session = pipeline.open(const MidiInputOptions());
        pipeline.receive(bytes('f8'));
        final events = session.events.toList();
        pipeline
          ..receive(bytes('fa'))
          ..end();
        expect([
          for (final event in await events) event.message,
        ], equals([const MidiStart()]));
      });

      test('reports faults of the stream once per decode stage', () {
        final pipeline = pipelineOf(bytePort());
        pipeline.open(const MidiInputOptions()).events.listen((_) {});
        pipeline.open(const MidiInputOptions()).events.listen((_) {});
        pipeline.receive(bytes('3c', 1));
        expect(
          diagnostics,
          equals([
            const MidiDiagnostic(
              kind: MidiDiagnosticKind.invalidData,
              port: byteId,
              cause: '1 data byte without status',
              time: MidiTime(77),
            ),
          ]),
        );
        pipeline
            .open(const MidiInputOptions(maxSysExLength: 8))
            .events
            .listen((_) {});
        pipeline.receive(bytes('3c', 1));
        expect(kinds(), hasLength(3));
      });

      test('drops values beyond the queue capacity', () async {
        final pipeline = pipelineOf(bytePort());
        final session = pipeline.open(const MidiInputOptions(queueCapacity: 2));
        final received = <MidiEvent>[];
        final subscription = session.events.listen(received.add)..pause();
        pipeline.receive(bytes('f8 f8 f8 f8'));
        await pumpEventQueue();
        expect(
          diagnostics,
          equals([
            const MidiDiagnostic(
              kind: MidiDiagnosticKind.queueOverflow,
              port: byteId,
              count: 2,
              cause:
                  'An input session dropped 2 events beyond its capacity '
                  'of 2',
              time: MidiTime(77),
            ),
          ]),
        );
        subscription.resume();
        await pumpEventQueue();
        expect(received, hasLength(2));
      });

      test('drops packets beyond the queue capacity', () async {
        final pipeline = pipelineOf(bytePort());
        pipeline
            .open(const MidiInputOptions(queueCapacity: 1))
            .packets
            .listen((_) {})
            .pause();
        pipeline
          ..receive(bytes('f8'))
          ..receive(bytes('f8'));
        await pumpEventQueue();
        expect(diagnostics.single.cause, contains('dropped 1 packets'));
      });
    });

    group('MidiInputOptions.deliverAs', () {
      test('midi2 translates MIDI 1.0 with the context of the port', () async {
        final pipeline = pipelineOf(bytePort(group: 3));
        final events = pipeline
            .open(const MidiInputOptions(deliverAs: MidiProtocol.midi2))
            .events
            .toList();
        const sent = [
          MidiNoteOn(channel: 0, note: 60, velocity: 100),
          MidiNoteOn(channel: 0, note: 60, velocity: 0),
          MidiControlChange(channel: 1, controller: 101, value: 0),
          MidiControlChange(channel: 1, controller: 100, value: 0),
          MidiControlChange(channel: 1, controller: 6, value: 2),
          MidiControlChange(channel: 1, controller: 38, value: 0),
          MidiTimingClock(),
        ];
        pipeline
          ..receive(bytes('90 3c 64 90 3c 00 b1 65 00 64 00 06 02 26 00 f8'))
          ..end();
        final oracle = MidiTranslator1To2();
        final expected = [
          for (final message in sent) ...oracle.translate(message, group: 3),
        ];
        final received = await events;
        expect([for (final event in received) event.message], expected);
        expect(received.map((event) => event.group).toSet(), equals({3}));
      });

      test('midi1 translates MIDI 2.0 down and reports drops', () async {
        final pipeline = pipelineOf(umpPort());
        final events = pipeline
            .open(const MidiInputOptions(deliverAs: MidiProtocol.midi1))
            .events
            .toList();
        const sent = [
          MidiNoteOn2(channel: 0, note: 60, velocity: 0xFFFF),
          MidiPerNotePitchBend(channel: 0, note: 60, value: 0),
          MidiStart(),
        ];
        pipeline
          ..receive(ump(sent))
          ..end();
        expect(
          [for (final event in await events) event.message],
          equals([
            const MidiNoteOn(channel: 0, note: 60, velocity: 127),
            const MidiStart(),
          ]),
        );
        expect(kinds(), equals([MidiDiagnosticKind.untranslatable]));
        expect(diagnostics.single.port, umpId);
      });

      test('delivers nothing while the translator holds the context', () {
        final pipeline = pipelineOf(bytePort());
        final received = <MidiEvent>[];
        pipeline
            .open(const MidiInputOptions(deliverAs: MidiProtocol.midi2))
            .events
            .listen(received.add);
        pipeline.receive(bytes('b0 65 00'));
        expect(received, isEmpty);
      });
    });

    group('MidiInputOptions.noteOnZeroAsNoteOff', () {
      test('turns Note On with velocity 0 into Note Off', () async {
        final pipeline = pipelineOf(bytePort());
        final events = pipeline
            .open(const MidiInputOptions(noteOnZeroAsNoteOff: true))
            .events
            .toList();
        pipeline
          ..receive(bytes('90 3c 00 90 3c 01'))
          ..end();
        expect(
          [for (final event in await events) event.message],
          equals([
            const MidiNoteOff(channel: 0, note: 60),
            const MidiNoteOn(channel: 0, note: 60, velocity: 1),
          ]),
        );
      });
    });

    group('reset()', () {
      test('drops partial messages', () async {
        final pipeline = pipelineOf(bytePort());
        final events = pipeline.open(const MidiInputOptions()).events.toList();
        pipeline
          ..receive(bytes('f0 01'))
          ..reset()
          ..receive(bytes('f0 02 f7'))
          ..end();
        expect(
          [for (final event in await events) event.message],
          equals([
            MidiSysEx([0x02]),
          ]),
        );
      });
    });

    group('update(port)', () {
      test('resets the stream state when the group changes', () async {
        final pipeline = pipelineOf(bytePort());
        final events = pipeline.open(const MidiInputOptions()).events.toList();
        pipeline
          ..receive(bytes('f0 01'))
          ..update(bytePort(group: 7))
          ..receive(bytes('f0 02 f7'))
          ..end();
        final received = await events;
        expect(received.single.message, MidiSysEx([0x02]));
        expect(received.single.group, 7);
        expect(pipeline.port.group, 7);
      });

      test('keeps the stream state for other changes', () async {
        final pipeline = pipelineOf(bytePort());
        final events = pipeline.open(const MidiInputOptions()).events.toList();
        pipeline
          ..receive(bytes('f0 01'))
          ..update(bytePort().copyWith(name: 'renamed'))
          ..receive(bytes('02 f7'))
          ..end();
        expect((await events).single.message, MidiSysEx([0x01, 0x02]));
      });

      test('resets for a new raw form or protocol', () {
        final pipeline = pipelineOf(umpPort());
        pipeline
          ..update(umpPort(protocol: MidiProtocol.midi1))
          ..update(bytePort());
        expect(pipeline.port, bytePort());
      });
    });

    group('end()', () {
      test('closes the sessions after their queued values', () async {
        final pipeline = pipelineOf(bytePort());
        final session = pipeline.open(const MidiInputOptions());
        final events = session.events.toList();
        final packets = session.packets.toList();
        pipeline
          ..receive(bytes('f8'))
          ..end();
        expect(session.isClosed, isTrue);
        expect(pipeline.isEmpty, isTrue);
        await session.done;
        expect([(await events).length, (await packets).length], [1, 1]);
        await session.close();
        expect(emptied, 0);
      });
    });

    group('close()', () {
      test('closes the sessions at once', () async {
        final pipeline = pipelineOf(bytePort());
        final session = pipeline.open(const MidiInputOptions());
        final events = session.events.toList();
        pipeline
          ..receive(bytes('f8'))
          ..close();
        expect(await events, isEmpty);
        expect(session.isClosed, isTrue);
      });
    });

    group('MidiInputSession', () {
      group('close()', () {
        test('detaches the session and empties the pipeline last', () async {
          final pipeline = pipelineOf(bytePort());
          final first = pipeline.open(const MidiInputOptions());
          final second = pipeline.open(
            const MidiInputOptions(deliverAs: MidiProtocol.midi2),
          );
          final third = pipeline.open(
            const MidiInputOptions(maxSysExLength: 9),
          );
          first.events.listen((_) {});
          second.events.listen((_) {});
          third.packets.listen((_) {});
          await first.close();
          await first.close();
          expect(emptied, 0);
          pipeline.receive(bytes('3c'));
          expect(kinds(), equals([MidiDiagnosticKind.invalidData]));
          await second.close();
          pipeline.receive(bytes('3c'));
          expect(kinds(), hasLength(1));
          await third.close();
          expect(emptied, 1);
          expect(pipeline.isEmpty, isTrue);
          await first.done;
        });

        test('keeps a delivery for its other sessions', () async {
          final pipeline = pipelineOf(bytePort());
          final first = pipeline.open(const MidiInputOptions());
          final second = pipeline.open(const MidiInputOptions());
          first.events.listen((_) {});
          final events = second.events.toList();
          await first.close();
          pipeline
            ..receive(bytes('f8'))
            ..end();
          expect(await events, hasLength(1));
        });
      });

      group('events, packets', () {
        test('are done when read after close', () async {
          final pipeline = pipelineOf(bytePort());
          final session = pipeline.open(const MidiInputOptions());
          await session.close();
          expect(await session.events.toList(), isEmpty);
          expect(await session.packets.toList(), isEmpty);
          expect(emptied, 1);
        });
      });
    });
  });
}
