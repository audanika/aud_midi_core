// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_core/src/engine/midi_output_pipeline.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  const outId = MidiPortId('fake:out');
  late MidiFakeClock clock;
  late MidiFakeTimers timers;
  late MidiSoftwareScheduler scheduler;
  late List<MidiDiagnostic> diagnostics;
  late List<(MidiPacket, MidiTime)> sent;
  late int cancelled;
  late int emptied;
  Object? cancelError;
  MidiOutputPipeline? current;

  // An output port with [capabilities], [protocol] and [group].
  MidiPortInfo port({
    MidiPortCapabilities capabilities = const MidiPortCapabilities(),
    MidiProtocol protocol = MidiProtocol.midi1,
    int group = 0,
  }) => MidiPortInfo(
    id: outId,
    name: 'out',
    direction: MidiDirection.output,
    capabilities: capabilities,
    protocol: protocol,
    group: group,
  );

  // A UMP port of [protocol].
  MidiPortInfo umpPort({
    MidiProtocol protocol = MidiProtocol.midi2,
    bool sysEx8 = false,
  }) => port(
    capabilities: MidiPortCapabilities(ump: true, sysEx8: sysEx8),
    protocol: protocol,
  );

  // A byte port that schedules in the operating system.
  MidiPortInfo scheduledPort({required bool cancel}) => port(
    capabilities: MidiPortCapabilities(
      scheduledSend: true,
      cancelPending: cancel,
    ),
  );

  // Records a packet handed to the backend with the clock time.
  Future<void> send(MidiPortId id, MidiPacket packet) async {
    expect(id, outId);
    sent.add((packet, clock.now()));
  }

  // Counts the calls to discard the packets of the backend.
  Future<void> cancelBackend(MidiPortId id) async {
    final error = cancelError;
    if (error != null) throw error;
    cancelled++;
  }

  // Returns a pipeline of [info] with the recording backend functions; the
  // scheduler reports its handoffs to it like the engine does.
  MidiOutputPipeline pipelineOf(
    MidiPortInfo info, {
    bool flushDataEntryMsb = false,
    Duration? lookahead,
  }) => current = MidiOutputPipeline(
    port: info,
    clock: clock,
    scheduler: scheduler,
    send: send,
    cancelBackend: cancelBackend,
    onDiagnostic: diagnostics.add,
    onEmpty: () async => emptied++,
    flushDataEntryMsb: flushDataEntryMsb,
    lookahead: lookahead,
  );

  // The words of [messages] encoded for [group].
  List<int> words(Iterable<MidiMessage> messages, {int group = 0}) => [
    for (final message in messages)
      for (final ump in UmpEncoder.encode(message, group: group)) ...ump.words,
  ];

  // The messages and groups of a UMP packet.
  List<(MidiMessage, int?)> decoded(MidiPacket packet) => [
    for (final message in UmpDecoder().add((packet as MidiUmpPacket).words))
      (message.message, message.group),
  ];

  // The sent packets without their send times.
  List<MidiPacket> packets() => [for (final (packet, _) in sent) packet];

  // The kinds of the diagnostics so far.
  List<MidiDiagnosticKind> kinds() => [
    for (final diagnostic in diagnostics) diagnostic.kind,
  ];

  setUp(() {
    clock = MidiFakeClock(start: const MidiTime(1000));
    timers = MidiFakeTimers(clock: clock);
    sent = [];
    diagnostics = [];
    cancelled = 0;
    emptied = 0;
    cancelError = null;
    current = null;
    scheduler = MidiSoftwareScheduler(
      clock: clock,
      dispatch: (id, packet) {
        current?.handedOver(packet);
        unawaited(send(id, packet));
      },
      timerFactory: timers.create,
    );
  });

  group('MidiOutputPipeline', () {
    group('open()', () {
      test('returns an open session of the port', () {
        final pipeline = pipelineOf(port());
        expect(pipeline.isEmpty, isTrue);
        final session = pipeline.open();
        expect([session.port, session.isClosed], equals([port(), false]));
        expect(pipeline.isEmpty, isFalse);
        expect([
          pipeline.clock,
          pipeline.scheduler,
        ], equals([clock, scheduler]));
        expect(pipeline.flushDataEntryMsb, isFalse);
        expect(pipeline.lookahead, isNull);
      });
    });

    group('sendMessages(messages, {at, group})', () {
      test('sends one bytes packet now, MIDI 2.0 translated down', () async {
        await pipelineOf(port()).sendMessages(const [
          MidiNoteOn(channel: 0, note: 60, velocity: 100),
          MidiNoteOn2(channel: 1, note: 62, velocity: 0xFFFF),
        ]);
        expect(
          sent,
          equals([
            (
              MidiBytesPacket(
                bytes: MidiBytes.fromHex('90 3c 64 91 3e 7f'),
                time: const MidiTime(1000),
              ),
              const MidiTime(1000),
            ),
          ]),
        );
      });

      test('drops what a byte port cannot carry', () async {
        await pipelineOf(port()).sendMessages(const [
          MidiJrClock(time: 1),
          MidiPerNotePitchBend(channel: 0, note: 1, value: 0),
        ]);
        expect(sent, isEmpty);
        expect(
          kinds(),
          equals([
            MidiDiagnosticKind.untranslatable,
            MidiDiagnosticKind.untranslatable,
          ]),
        );
        expect(
          diagnostics.first.cause,
          'MidiJrClock has no MIDI 1.0 byte form',
        );
        expect(diagnostics.first.port, outId);
      });

      test('translates up for a MIDI 2.0 port, with context', () async {
        final pipeline = pipelineOf(umpPort());
        const messages = [
          MidiNoteOn(channel: 0, note: 60, velocity: 100),
          MidiControlChange(channel: 0, controller: 101, value: 0),
          MidiControlChange(channel: 0, controller: 100, value: 0),
          MidiControlChange(channel: 0, controller: 6, value: 2),
          MidiControlChange(channel: 0, controller: 38, value: 0),
        ];
        await pipeline.sendMessages(messages, group: 4);
        final oracle = MidiTranslator1To2();
        expect(
          packets(),
          equals([
            MidiUmpPacket(
              words: words([
                for (final message in messages)
                  ...oracle.translate(message, group: 4),
              ], group: 4),
              time: const MidiTime(1000),
            ),
          ]),
        );
      });

      test('uses the alternate translation when told to', () async {
        final pipeline = pipelineOf(umpPort(), flushDataEntryMsb: true);
        const messages = [
          MidiControlChange(channel: 0, controller: 101, value: 0),
          MidiControlChange(channel: 0, controller: 100, value: 0),
          MidiControlChange(channel: 0, controller: 6, value: 2),
          MidiControlChange(channel: 0, controller: 101, value: 1),
        ];
        await pipeline.sendMessages(messages);
        final oracle = MidiTranslator1To2(flushDataEntryMsb: true);
        expect(
          packets(),
          equals([
            MidiUmpPacket(
              words: words([
                for (final message in messages) ...oracle.translate(message),
              ]),
              time: const MidiTime(1000),
            ),
          ]),
        );
      });

      test('translates down for a MIDI 1.0 UMP port', () async {
        await pipelineOf(umpPort(protocol: MidiProtocol.midi1)).sendMessages(
          const [MidiNoteOn2(channel: 0, note: 60, velocity: 0xFFFF)],
        );
        expect(
          decoded(packets().single),
          equals([(const MidiNoteOn(channel: 0, note: 60, velocity: 127), 0)]),
        );
      });

      test('passes System Exclusive 8 only to capable ports', () async {
        final sysEx8 = MidiSysEx8(streamId: 1, data: [1, 2]);
        await pipelineOf(umpPort()).sendMessages([sysEx8]);
        expect(sent, isEmpty);
        expect(kinds(), equals([MidiDiagnosticKind.untranslatable]));
        await pipelineOf(umpPort(sysEx8: true)).sendMessages([sysEx8]);
        expect(decoded(packets().single), equals([(sysEx8, 0)]));
      });

      test('ignores the group on byte ports', () async {
        await pipelineOf(
          port(group: 3),
        ).sendMessages(const [MidiStart()], group: 9);
        expect(
          packets(),
          equals([
            MidiBytesPacket(
              bytes: MidiBytes([0xFA]),
              time: const MidiTime(1000),
            ),
          ]),
        );
      });
    });

    group('scheduling', () {
      test('holds future packets in software until they are due', () async {
        final pipeline = pipelineOf(port());
        await pipeline.sendMessages(const [
          MidiStart(),
        ], at: const MidiTime(3000));
        expect(sent, isEmpty);
        timers.advance(const Duration(milliseconds: 2));
        await pumpEventQueue();
        expect(
          sent,
          equals([
            (
              MidiBytesPacket(
                bytes: MidiBytes([0xFA]),
                time: const MidiTime(3000),
              ),
              const MidiTime(3000),
            ),
          ]),
        );
      });

      test('sends due packets before an immediate one', () async {
        final pipeline = pipelineOf(port());
        await pipeline.sendMessages(const [
          MidiStart(),
        ], at: const MidiTime(2000));
        clock.advance(const Duration(milliseconds: 2));
        await pipeline.sendMessages(const [MidiStop()]);
        await pumpEventQueue();
        expect([
          for (final packet in packets()) (packet as MidiBytesPacket).bytes[0],
        ], equals([0xFA, 0xFC]));
      });

      test('hands future packets to a port that schedules', () async {
        await pipelineOf(
          scheduledPort(cancel: true),
        ).sendMessages(const [MidiStart()], at: const MidiTime(9000));
        expect(
          sent,
          equals([
            (
              MidiBytesPacket(
                bytes: MidiBytes([0xFA]),
                time: const MidiTime(9000),
              ),
              const MidiTime(1000),
            ),
          ]),
        );
      });

      test('hands packets over at once without lookahead', () async {
        final pipeline = pipelineOf(scheduledPort(cancel: false));
        await pipeline.sendMessages(const [
          MidiStart(),
        ], at: const MidiTime(9000));
        expect(sent.single.$2, const MidiTime(1000));
        expect(await pipeline.cancelPending(), 1);
      });

      test('keeps packets cancellable until the lookahead', () async {
        final pipeline = pipelineOf(
          scheduledPort(cancel: false),
          lookahead: const Duration(milliseconds: 3),
        );
        for (final at in [9000, 10000]) {
          await pipeline.sendMessages(const [MidiStart()], at: MidiTime(at));
        }
        expect(sent, isEmpty);
        expect(scheduler.pending(), 2);
        timers.advance(const Duration(milliseconds: 5));
        await pumpEventQueue();
        expect(
          sent,
          equals([
            (
              MidiBytesPacket(
                bytes: MidiBytes([0xFA]),
                time: const MidiTime(9000),
              ),
              const MidiTime(6000),
            ),
          ]),
        );
        expect(await pipeline.cancelPending(), 1);
        timers.advance(const Duration(milliseconds: 5));
        expect(sent, hasLength(1));
      });

      test('hands packets within the lookahead over at once', () async {
        final pipeline = pipelineOf(
          scheduledPort(cancel: false),
          lookahead: const Duration(milliseconds: 3),
        );
        await pipeline.sendMessages(const [
          MidiStart(),
        ], at: const MidiTime(9000));
        clock.jumpTo(const MidiTime(6500));
        await pipeline.sendMessages(const [
          MidiStop(),
        ], at: const MidiTime(8000));
        expect([
          for (final packet in packets()) packet.time,
        ], equals([const MidiTime(9000), const MidiTime(8000)]));
        expect(await pipeline.cancelPending(), 2);
      });

      test('schedules in software with a zero lookahead', () async {
        final pipeline = pipelineOf(
          scheduledPort(cancel: false),
          lookahead: Duration.zero,
        );
        await pipeline.sendMessages(const [
          MidiStart(),
        ], at: const MidiTime(9000));
        expect(sent, isEmpty);
        expect(scheduler.pending(), 1);
        expect(await pipeline.cancelPending(), 0);
        expect(scheduler.pending(), 0);
      });

      test('ignores handoffs for ports that can discard', () async {
        final pipeline = pipelineOf(scheduledPort(cancel: true))
          ..handedOver(
            MidiBytesPacket(
              bytes: MidiBytes([0xFA]),
              time: const MidiTime(9000),
            ),
          );
        expect(await pipeline.cancelPending(), 0);
      });
    });

    group('cancelPending()', () {
      test('discards the software queue', () async {
        final pipeline = pipelineOf(port());
        await pipeline.sendMessages(const [
          MidiStart(),
        ], at: const MidiTime(5000));
        expect(await pipeline.cancelPending(), 0);
        timers.advance(const Duration(milliseconds: 10));
        expect(sent, isEmpty);
        expect(cancelled, 0);
      });

      test('asks a capable backend to discard', () async {
        final pipeline = pipelineOf(scheduledPort(cancel: true));
        await pipeline.sendMessages(const [
          MidiStart(),
        ], at: const MidiTime(5000));
        expect(await pipeline.cancelPending(), 0);
        expect(cancelled, 1);
      });

      test('counts what a port that cannot discard still holds', () async {
        final pipeline = pipelineOf(scheduledPort(cancel: false));
        for (final at in [500, 2000, 4000]) {
          await pipeline.sendMessages(const [MidiStart()], at: MidiTime(at));
        }
        expect(await pipeline.cancelPending(), 2);
        clock.jumpTo(const MidiTime(2000));
        expect(await pipeline.cancelPending(), 1);
        expect(cancelled, 0);
      });
    });

    group('panic(panic)', () {
      test('turns the tracked notes off on a byte port', () async {
        final pipeline = pipelineOf(port());
        await pipeline.sendMessages(const [
          MidiNoteOn(channel: 1, note: 60, velocity: 1),
        ]);
        await pipeline.sendMessages(const [
          MidiNoteOn(channel: 1, note: 62, velocity: 1),
        ], at: const MidiTime(5000));
        sent.clear();
        await pipeline.panic(const MidiPanic(channels: [1]));
        expect(
          packets(),
          equals([
            MidiBytesPacket(
              bytes: MidiBytes.fromHex(
                '81 3c 40 81 3e 40 b1 78 00 b1 79 00 b1 7b 00',
              ),
              time: const MidiTime(1000),
            ),
          ]),
        );
        timers.advance(const Duration(milliseconds: 5));
        expect(sent, hasLength(1));
        sent.clear();
        await pipeline.panic(
          const MidiPanic(channels: [1], allSoundOff: false),
        );
        expect(
          (packets().single as MidiBytesPacket).bytes,
          MidiBytes.fromHex('b1 79 00 b1 7b 00'),
        );
      });

      test('silences every group with notes on a UMP port', () async {
        final pipeline = pipelineOf(umpPort());
        await pipeline.sendMessages(const [
          MidiNoteOn(channel: 0, note: 60, velocity: 1),
        ], group: 2);
        sent.clear();
        await pipeline.panic(
          const MidiPanic(
            channels: [0],
            allSoundOff: false,
            resetAllControllers: false,
            allNotesOff: false,
          ),
        );
        expect(packets(), hasLength(1));
        expect(
          decoded(packets().single),
          equals([
            (
              MidiTranslator1To2()
                  .translate(const MidiNoteOff(channel: 0, note: 60))
                  .single,
              2,
            ),
          ]),
        );
      });

      test('repeats after the packets a port cannot discard', () async {
        final pipeline = pipelineOf(scheduledPort(cancel: false));
        await pipeline.sendMessages(const [
          MidiNoteOn(channel: 0, note: 60, velocity: 1),
        ], at: const MidiTime(9000));
        sent.clear();
        const panic = MidiPanic(
          channels: [0],
          allSoundOff: false,
          resetAllControllers: false,
        );
        await pipeline.panic(panic);
        expect(
          packets(),
          equals([
            MidiBytesPacket(
              bytes: MidiBytes.fromHex('80 3c 40 b0 7b 00'),
              time: const MidiTime(1000),
            ),
            MidiBytesPacket(
              bytes: MidiBytes.fromHex('80 3c 40 b0 7b 00'),
              time: const MidiTime(10000),
            ),
          ]),
        );
      });

      test('keeps pending packets when told to', () async {
        final pipeline = pipelineOf(scheduledPort(cancel: false));
        await pipeline.sendMessages(const [
          MidiStart(),
        ], at: const MidiTime(9000));
        sent.clear();
        await pipeline.panic(
          const MidiPanic(channels: [0], noteOffs: false, cancelPending: false),
        );
        expect(sent, hasLength(1));
        expect(await pipeline.cancelPending(), 1);
      });
    });

    group('sendPacket(packet)', () {
      test('sends a packet of the port form unchanged', () async {
        final packet = MidiBytesPacket(
          bytes: MidiBytes([0xF8]),
          time: const MidiTime(500),
        );
        await pipelineOf(port()).sendPacket(packet);
        expect(packets(), equals([packet]));
      });

      test('converts bytes for a UMP port', () async {
        await pipelineOf(umpPort(protocol: MidiProtocol.midi1)).sendPacket(
          MidiBytesPacket(
            bytes: MidiBytes.fromHex('90 3c 64'),
            time: const MidiTime(500),
          ),
        );
        expect(
          packets(),
          equals([
            MidiUmpPacket(
              words: words(const [
                MidiNoteOn(channel: 0, note: 60, velocity: 100),
              ]),
              time: const MidiTime(500),
            ),
          ]),
        );
      });

      test('converts UMP for a byte port', () async {
        await pipelineOf(port()).sendPacket(
          MidiUmpPacket(
            words: words(const [
              MidiNoteOn2(channel: 0, note: 60, velocity: 0xFFFF),
            ]),
            time: const MidiTime(500),
          ),
        );
        expect(
          packets(),
          equals([
            MidiBytesPacket(
              bytes: MidiBytes.fromHex('90 3c 7f'),
              time: const MidiTime(500),
            ),
          ]),
        );
      });

      test('sends nothing when no message is left', () async {
        await pipelineOf(port()).sendPacket(
          MidiUmpPacket(
            words: words(const [MidiJrClock(time: 1)]),
            time: MidiTime.zero,
          ),
        );
        expect(sent, isEmpty);
      });
    });

    group('update(port)', () {
      test('keeps the translation context for other changes', () async {
        final pipeline = pipelineOf(umpPort());
        await pipeline.sendMessages(const [
          MidiControlChange(channel: 0, controller: 101, value: 0),
          MidiControlChange(channel: 0, controller: 100, value: 0),
          MidiControlChange(channel: 0, controller: 6, value: 1),
        ]);
        pipeline.update(umpPort().copyWith(name: 'renamed'));
        await pipeline.sendMessages(const [
          MidiControlChange(channel: 0, controller: 38, value: 0),
        ]);
        expect(packets(), hasLength(1));
        expect(pipeline.port.name, 'renamed');
      });

      test('resets the translation context for a new protocol', () async {
        final pipeline = pipelineOf(umpPort());
        await pipeline.sendMessages(const [
          MidiControlChange(channel: 0, controller: 101, value: 0),
          MidiControlChange(channel: 0, controller: 100, value: 0),
          MidiControlChange(channel: 0, controller: 6, value: 1),
        ]);
        pipeline
          ..update(umpPort(protocol: MidiProtocol.midi1))
          ..update(umpPort());
        await pipeline.sendMessages(const [
          MidiControlChange(channel: 0, controller: 38, value: 0),
        ]);
        expect(sent, isEmpty);
      });
    });

    group('end(), close()', () {
      for (final (name, gone) in [('end', true), ('close', false)]) {
        test('$name() closes the sessions and drops the queue', () async {
          final pipeline = pipelineOf(port());
          final session = pipeline.open();
          await session.send(const MidiStart(), at: const MidiTime(5000));
          if (gone) {
            pipeline.end();
          } else {
            pipeline.close();
          }
          await session.done;
          expect([session.isClosed, pipeline.isEmpty], equals([true, true]));
          expect(scheduler.pending(), 0);
          expect(
            () => session.send(const MidiStop()),
            throwsA(gone ? isA<MidiPortGone>() : isA<StateError>()),
          );
          await session.close();
          expect(emptied, 0);
        });
      }
    });

    group('MidiOutputSession', () {
      test('sends through the pipeline', () async {
        final session = pipelineOf(port()).open();
        await session.send(const MidiStart());
        await session.sendAll(const [MidiStop(), MidiContinue()]);
        await session.sendPacket(
          MidiBytesPacket(bytes: MidiBytes([0xF8]), time: MidiTime.zero),
        );
        await session.send(const MidiStart(), at: const MidiTime(5000));
        expect(await session.cancelPending(), 0);
        await session.panic(
          panic: const MidiPanic(channels: [0], noteOffs: false),
        );
        expect(
          [for (final packet in packets()) (packet as MidiBytesPacket).bytes],
          equals([
            MidiBytes([0xFA]),
            MidiBytes([0xFC, 0xFB]),
            MidiBytes([0xF8]),
            MidiBytes.fromHex('b0 78 00 b0 79 00 b0 7b 00'),
          ]),
        );
      });

      group('close()', () {
        test('empties the pipeline with the last session', () async {
          final pipeline = pipelineOf(scheduledPort(cancel: true));
          final first = pipeline.open();
          final second = pipeline.open();
          await first.close();
          await first.close();
          expect([emptied, cancelled], equals([0, 0]));
          await second.close();
          expect([emptied, cancelled], equals([1, 1]));
          expect(
            () => first.send(const MidiStart()),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                'The output session of fake:out is closed',
              ),
            ),
          );
        });

        test('reports a failure to discard and empties anyway', () async {
          cancelError = StateError('busy');
          final session = pipelineOf(scheduledPort(cancel: true)).open();
          await session.close();
          expect(emptied, 1);
          expect(
            diagnostics.single.cause,
            'Discarding the pending packets failed: Bad state: busy',
          );
          expect(kinds(), equals([MidiDiagnosticKind.nativeError]));
        });
      });

      test('every method throws once the port is gone', () async {
        final pipeline = pipelineOf(port());
        final session = pipeline.open();
        pipeline.end();
        for (final call in <Future<Object?> Function()>[
          () => session.send(const MidiStart()),
          () => session.sendAll(const [MidiStart()]),
          () => session.sendPacket(
            MidiBytesPacket(bytes: MidiBytes([0xF8]), time: MidiTime.zero),
          ),
          session.cancelPending,
          session.panic,
        ]) {
          await expectLater(
            call(),
            throwsA(isA<MidiPortGone>().having((e) => e.port, 'port', outId)),
          );
        }
      });
    });
  });
}
