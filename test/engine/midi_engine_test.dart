// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  const start = MidiTime(1000000);
  late MidiFakeClock clock;
  late MidiFakeTimers timers;
  late FakeMidiBackend backend;
  late MidiPortInfo input;
  late MidiPortInfo output;
  late MidiPortInfo umpInput;
  late MidiPortInfo umpOutput;
  late MidiPortInfo scheduled;
  late MidiEngine engine;
  late List<MidiDiagnostic> diagnostics;
  late List<MidiPortEvent> portEvents;

  // Creates the engine with [options], records its streams and opens it.
  Future<void> open({
    MidiEngineOptions options = const MidiEngineOptions(),
  }) async {
    engine = MidiEngine(
      backend: backend,
      clock: clock,
      options: options,
      timerFactory: timers.create,
    );
    engine.diagnostics.listen(diagnostics.add);
    engine.portEvents.listen(portEvents.add);
    await engine.open();
  }

  // A bytes packet of [hex] received at [time].
  MidiPacket bytes(String hex, [MidiTime time = start]) =>
      MidiBytesPacket(bytes: MidiBytes.fromHex(hex), time: time);

  // The messages of [events].
  List<MidiMessage> messagesOf(List<MidiEvent> events) => [
    for (final event in events) event.message,
  ];

  // The first bytes of the sent packets.
  List<int> sentStatus() => [
    for (final sent in backend.sent) (sent.packet as MidiBytesPacket).bytes[0],
  ];

  // The kinds of the diagnostics so far.
  List<MidiDiagnosticKind> kinds() => [
    for (final diagnostic in diagnostics) diagnostic.kind,
  ];

  setUp(() {
    clock = MidiFakeClock(start: start);
    timers = MidiFakeTimers(clock: clock);
    diagnostics = [];
    portEvents = [];
    backend = FakeMidiBackend(timerFactory: timers.create);
    input = backend.addPort(
      backend.portInfo('in', direction: MidiDirection.input, group: 2),
    );
    output = backend.addPort(
      backend.portInfo('out', direction: MidiDirection.output),
    );
    const ump = MidiPortCapabilities(ump: true);
    umpInput = backend.addPort(
      backend.portInfo(
        'umpIn',
        direction: MidiDirection.input,
        protocol: MidiProtocol.midi2,
        capabilities: ump,
      ),
    );
    umpOutput = backend.addPort(
      backend.portInfo(
        'umpOut',
        direction: MidiDirection.output,
        protocol: MidiProtocol.midi2,
        capabilities: ump,
      ),
    );
    scheduled = backend.addPort(
      backend.portInfo(
        'scheduled',
        direction: MidiDirection.output,
        capabilities: const MidiPortCapabilities(
          scheduledSend: true,
          cancelPending: true,
        ),
      ),
    );
    backend
      ..connectLoopback(output.id, input.id)
      ..connectLoopback(umpOutput.id, umpInput.id);
  });

  group('MidiEngine', () {
    group('MidiEngine({backend, clock, options, timerFactory})', () {
      test('uses the system clock and default options', () {
        final plain = MidiEngine(backend: backend);
        expect(plain.clock, isA<MidiSystemClock>());
        expect(plain.options, const MidiEngineOptions());
        expect(plain.backend, same(backend));
        expect([plain.isOpen, plain.isClosed], equals([false, false]));
        expect(plain.ports, isEmpty);
        expect(plain.capabilities, backend.capabilities);
        expect(plain.virtualPorts, same(backend.virtualPorts));
        expect(plain.bluetooth, same(backend.bluetooth));
        expect(plain.network, same(backend.network));
      });
    });

    group('open()', () {
      test('starts the backend and takes over its ports', () async {
        await open();
        expect(engine.isOpen, isTrue);
        expect(backend.isStarted, isTrue);
        expect(
          engine.ports,
          equals([input, output, umpInput, umpOutput, scheduled]),
        );
        expect(engine.inputs, equals([input, umpInput]));
        expect(engine.outputs, equals([output, umpOutput, scheduled]));
        expect(engine.port(input.id), input);
        expect(engine.port(const MidiPortId('fake:none')), isNull);
        expect(engine.devices, isEmpty);
        expect(portEvents, isEmpty);
      });

      test('can be called once only', () async {
        await open();
        await expectLater(engine.open(), throwsA(isA<StateError>()));
        await engine.close();
        await expectLater(engine.open(), throwsA(isA<StateError>()));
      });

      test('can be tried again after a failed start', () async {
        backend.failWith(start: StateError('no MIDI'));
        await expectLater(
          open(),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'no MIDI'),
          ),
        );
        expect(engine.isOpen, isFalse);
        backend.failWith();
        await engine.open();
        expect(engine.isOpen, isTrue);
      });
    });

    group('close()', () {
      test('shuts down in order', () async {
        await open();
        final inputSession = await engine.openInput(input.id);
        final outputSession = await engine.openOutput(scheduled.id);
        final events = inputSession.events.toList();
        backend.clearRecords();
        await engine.close();
        expect(
          backend.calls,
          equals([
            'closePort fake:in',
            'cancelPending fake:scheduled',
            'closePort fake:scheduled',
            'stop',
          ]),
        );
        expect(await events, isEmpty);
        expect([inputSession.isClosed, outputSession.isClosed], [true, true]);
        expect([engine.isOpen, engine.isClosed], equals([false, true]));
      });

      test('delivers no event after close', () async {
        await open();
        final session = await engine.openInput(input.id);
        final events = <MidiEvent>[];
        final subscription = session.events.listen(events.add)..pause();
        backend.inject(input.id, bytes('f8'));
        await engine.close();
        subscription.resume();
        expect(backend.inject(input.id, bytes('f8')), isFalse);
        backend.reportDiagnostic(
          const MidiDiagnostic(
            kind: MidiDiagnosticKind.nativeError,
            cause: 'late',
            time: start,
          ),
        );
        await pumpEventQueue();
        expect(events, isEmpty);
        expect(diagnostics, isEmpty);
        expect(await engine.portEvents.isEmpty, isTrue);
        expect(await engine.diagnostics.isEmpty, isTrue);
      });

      test('waits for the sends in flight', () async {
        await open();
        final session = await engine.openOutput(output.id);
        backend.holdCalls();
        final sending = session.send(const MidiStart());
        final closing = engine.close();
        await pumpEventQueue();
        expect(backend.calls, isNot(contains('stop')));
        backend.releaseCalls();
        await Future.wait([sending, closing]);
        expect(backend.calls.last, 'stop');
      });

      test('returns the same future when called again', () async {
        await open();
        final closing = engine.close();
        expect(engine.close(), same(closing));
        await closing;
      });

      test('closes an engine that never opened', () async {
        final plain = MidiEngine(backend: backend);
        await plain.close();
        expect(plain.isClosed, isTrue);
        expect(backend.calls, isEmpty);
      });

      test('waits for an open in progress', () async {
        engine = MidiEngine(backend: backend, clock: clock);
        final opening = engine.open();
        final closing = engine.close();
        await Future.wait([opening, closing]);
        expect(backend.calls, equals(['start', 'stop']));
      });

      test('finishes after a failed open', () async {
        engine = MidiEngine(backend: backend, clock: clock);
        backend.failWith(start: StateError('no MIDI'));
        final opening = engine.open();
        final closing = engine.close();
        await expectLater(opening, throwsA(isA<StateError>()));
        await closing;
        expect(backend.calls, equals(['start']));
      });

      test('reports failures and rethrows a failing stop', () async {
        await open();
        await engine.openInput(input.id);
        await engine.openOutput(scheduled.id);
        backend.failWith(
          closePort: StateError('busy'),
          cancelPending: StateError('full'),
          stop: StateError('stuck'),
        );
        await expectLater(
          engine.close(),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'stuck'),
          ),
        );
        expect(engine.isClosed, isTrue);
        expect(
          [for (final diagnostic in diagnostics) diagnostic.cause],
          equals([
            'Closing the port failed: Bad state: busy',
            'Discarding pending packets failed: Bad state: full',
            'Closing the port failed: Bad state: busy',
          ]),
        );
      });
    });

    group('openInput(id, {options})', () {
      test('throws for a closed engine, unknown ports and outputs', () async {
        engine = MidiEngine(backend: backend);
        await expectLater(engine.openInput(input.id), throwsStateError);
        await open();
        await expectLater(
          engine.openInput(const MidiPortId('fake:none')),
          throwsA(isA<MidiPortGone>()),
        );
        await expectLater(
          engine.openInput(output.id),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Not an input port',
            ),
          ),
        );
      });

      test('shares the native port between sessions', () async {
        await open();
        final first = await engine.openInput(input.id);
        final second = await engine.openInput(input.id);
        await first.close();
        expect(backend.openPorts, contains(input.id));
        await second.close();
        expect(
          backend.calls,
          equals(['start', 'openPort fake:in', 'closePort fake:in']),
        );
      });

      test('delivers typed events and raw packets of a loopback', () async {
        await open();
        final session = await engine.openInput(input.id);
        final events = session.events.toList();
        final packets = session.packets.toList();
        final sender = await engine.openOutput(output.id);
        await sender.send(const MidiNoteOn(channel: 0, note: 60, velocity: 9));
        await session.close();
        expect(
          await events,
          equals([
            MidiEvent(
              message: const MidiNoteOn(channel: 0, note: 60, velocity: 9),
              time: start,
              port: input.id,
              group: 2,
            ),
          ]),
        );
        expect(await packets, equals([bytes('90 3c 09')]));
      });

      test('reassembles System Exclusive around real-time bytes', () async {
        await open();
        final session = await engine.openInput(input.id);
        final events = <MidiEvent>[];
        session.events.listen(events.add);
        backend
          ..inject(input.id, bytes('f0 7e 7f'))
          ..inject(input.id, bytes('f8'))
          ..inject(input.id, bytes('06 01 f7'));
        await pumpEventQueue();
        expect(
          messagesOf(events),
          equals([
            const MidiTimingClock(),
            MidiSysEx([0x7e, 0x7f, 0x06, 0x01]),
          ]),
        );
      });

      test('translates MIDI 1.0 up and back down over UMP', () async {
        await open();
        final asReceived = await engine.openInput(umpInput.id);
        final asMidi1 = await engine.openInput(
          umpInput.id,
          options: const MidiInputOptions(deliverAs: MidiProtocol.midi1),
        );
        final received = <MidiEvent>[];
        final translated = <MidiEvent>[];
        asReceived.events.listen(received.add);
        asMidi1.events.listen(translated.add);
        final sender = await engine.openOutput(umpOutput.id);
        const note = MidiNoteOn(channel: 3, note: 64, velocity: 100);
        await sender.send(note);
        await pumpEventQueue();
        expect(messagesOf(received), equals(note.toMidi2()));
        expect(messagesOf(translated), equals([note]));
        expect(received.single.group, 0);
      });

      test('translates MIDI 2.0 down and up over bytes', () async {
        await open();
        final asMidi2 = await engine.openInput(
          input.id,
          options: const MidiInputOptions(deliverAs: MidiProtocol.midi2),
        );
        final events = <MidiEvent>[];
        asMidi2.events.listen(events.add);
        final sender = await engine.openOutput(output.id);
        await sender.send(
          const MidiNoteOn2(channel: 0, note: 60, velocity: 0xFFFF),
        );
        await pumpEventQueue();
        expect(
          messagesOf(events),
          equals([const MidiNoteOn2(channel: 0, note: 60, velocity: 0xFFFF)]),
        );
        expect(events.single.group, 2);
      });

      test('uses the input options of the engine by default', () async {
        const defaults = MidiInputOptions(noteOnZeroAsNoteOff: true);
        await open(options: const MidiEngineOptions(input: defaults));
        final session = await engine.openInput(input.id);
        expect(session.options, defaults);
        final events = <MidiEvent>[];
        session.events.listen(events.add);
        backend.inject(input.id, bytes('90 3c 00'));
        await pumpEventQueue();
        expect(
          messagesOf(events),
          equals([const MidiNoteOff(channel: 0, note: 60)]),
        );
      });

      test('drops events beyond the queue capacity', () async {
        await open();
        final session = await engine.openInput(
          input.id,
          options: const MidiInputOptions(queueCapacity: 1),
        );
        session.events.listen((_) {}).pause();
        backend.inject(input.id, bytes('f8 f8 f8'));
        await pumpEventQueue();
        expect(
          diagnostics,
          equals([
            MidiDiagnostic(
              kind: MidiDiagnosticKind.queueOverflow,
              port: input.id,
              count: 2,
              cause:
                  'An input session dropped 2 events beyond its capacity of '
                  '1',
              time: start,
            ),
          ]),
        );
        expect(
          engine.diagnosticsSnapshot().count(
            MidiDiagnosticKind.queueOverflow,
            port: input.id,
          ),
          2,
        );
      });

      test('fails when the port disappears while it opens', () async {
        await open();
        backend.holdCalls();
        final opening = engine.openInput(input.id);
        await pumpEventQueue();
        expect(backend.calls.last, 'openPort fake:in');
        backend
          ..removePort(input.id)
          ..releaseCalls();
        await expectLater(opening, throwsA(isA<MidiPortGone>()));
        expect(backend.calls.last, 'closePort fake:in');
      });
    });

    group('openOutput(id)', () {
      test('throws for a closed engine, unknown ports and inputs', () async {
        engine = MidiEngine(backend: backend);
        await expectLater(engine.openOutput(output.id), throwsStateError);
        await open();
        await expectLater(
          engine.openOutput(const MidiPortId('fake:none')),
          throwsA(isA<MidiPortGone>()),
        );
        await expectLater(
          engine.openOutput(input.id),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('shares the native port between sessions', () async {
        await open();
        final first = await engine.openOutput(output.id);
        final second = await engine.openOutput(output.id);
        await first.close();
        await second.close();
        expect(
          backend.calls,
          equals(['start', 'openPort fake:out', 'closePort fake:out']),
        );
      });

      test('schedules in software and delivers on time', () async {
        await open();
        final session = await engine.openInput(input.id);
        final events = <MidiEvent>[];
        session.events.listen(events.add);
        final sender = await engine.openOutput(output.id);
        final due = start + const Duration(milliseconds: 10);
        await sender.send(const MidiStart(), at: due);
        expect(backend.sent, isEmpty);
        timers.advance(const Duration(milliseconds: 10));
        await pumpEventQueue();
        expect(
          backend.sent,
          equals([
            (
              port: output.id,
              packet: MidiBytesPacket(bytes: MidiBytes([0xFA]), time: due),
              sentAt: due,
            ),
          ]),
        );
        expect(events.single.time, due);
        expect(diagnostics, isEmpty);
      });

      test('keeps the order of the sends of a port', () async {
        await open();
        final sender = await engine.openOutput(output.id);
        final later = start + const Duration(milliseconds: 5);
        await sender.send(const MidiStart(), at: later);
        await sender.send(const MidiContinue(), at: later);
        await sender.send(const MidiTimingClock());
        await sender.send(
          const MidiStop(),
          at: start + const Duration(milliseconds: 2),
        );
        timers.advance(const Duration(milliseconds: 5));
        await pumpEventQueue();
        expect(sentStatus(), equals([0xF8, 0xFC, 0xFA, 0xFB]));
      });

      test('hands future packets to a port that schedules', () async {
        await open();
        final sender = await engine.openOutput(scheduled.id);
        final due = start + const Duration(seconds: 1);
        await sender.send(const MidiStart(), at: due);
        expect(backend.sent.single.packet.time, due);
        expect(backend.sent.single.sentAt, start);
        expect(await sender.cancelPending(), 0);
        expect(backend.calls.last, 'cancelPending fake:scheduled');
      });

      test('reports late packets', () async {
        await open(
          options: const MidiEngineOptions(
            lateThreshold: Duration(milliseconds: 1),
          ),
        );
        final sender = await engine.openOutput(output.id);
        await sender.send(
          const MidiStart(),
          at: start + const Duration(milliseconds: 2),
        );
        clock.advance(const Duration(milliseconds: 5));
        timers.flush();
        await pumpEventQueue();
        expect(kinds(), equals([MidiDiagnosticKind.schedulerLate]));
        expect(diagnostics.single.port, output.id);
      });

      test('reports scheduled packets that fail', () async {
        await open();
        final sender = await engine.openOutput(output.id);
        await sender.send(
          const MidiStart(),
          at: start + const Duration(milliseconds: 1),
        );
        backend.failWith(send: StateError('unplugged'));
        timers.advance(const Duration(milliseconds: 1));
        await pumpEventQueue();
        expect(
          diagnostics.single.cause,
          'Sending a scheduled packet failed: Bad state: unplugged',
        );
      });

      test('passes a failed immediate send to the caller', () async {
        await open();
        final sender = await engine.openOutput(output.id);
        backend.failWith(send: StateError('unplugged'));
        await expectLater(
          sender.send(const MidiStart()),
          throwsA(isA<StateError>()),
        );
      });

      test(
        'keeps packets for an uncancellable port until the lookahead',
        () async {
          final uncancellable = backend.addPort(
            backend.portInfo(
              'virtual',
              direction: MidiDirection.output,
              capabilities: const MidiPortCapabilities(scheduledSend: true),
            ),
          );
          await open(
            options: const MidiEngineOptions(
              lookahead: Duration(milliseconds: 100),
            ),
          );
          final sender = await engine.openOutput(uncancellable.id);
          final first = start + const Duration(milliseconds: 300);
          final second = start + const Duration(milliseconds: 400);
          await sender.send(const MidiStart(), at: first);
          await sender.send(const MidiStop(), at: second);
          expect(backend.sent, isEmpty);
          timers.advance(const Duration(milliseconds: 200));
          await pumpEventQueue();
          expect(
            backend.sent,
            equals([
              (
                port: uncancellable.id,
                packet: MidiBytesPacket(bytes: MidiBytes([0xFA]), time: first),
                sentAt: start + const Duration(milliseconds: 200),
              ),
            ]),
          );
          expect(await sender.cancelPending(), 1);
          timers.advance(const Duration(milliseconds: 300));
          expect(backend.sent, hasLength(1));
          expect(diagnostics, isEmpty);
        },
      );
    });

    group('send, sendAll, sendPacket, cancelPending', () {
      test('use the open output with the id', () async {
        await open();
        await engine.openOutput(output.id);
        await engine.send(output.id, const MidiStart());
        await engine.sendAll(output.id, const [MidiStop(), MidiContinue()]);
        await engine.sendPacket(output.id, bytes('f8'));
        await engine.send(
          output.id,
          const MidiTimingClock(),
          at: start + const Duration(milliseconds: 1),
        );
        expect(await engine.cancelPending(output.id), 0);
        timers.advance(const Duration(milliseconds: 1));
        expect(sentStatus(), equals([0xFA, 0xFC, 0xF8]));
      });

      test('throw for unknown and unopened outputs', () async {
        await open();
        await expectLater(
          engine.send(const MidiPortId('fake:none'), const MidiStart()),
          throwsA(isA<MidiPortGone>()),
        );
        await expectLater(
          engine.send(output.id, const MidiStart()),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'The output fake:out is not open',
            ),
          ),
        );
      });
    });

    group('panic({panic})', () {
      test('silences every open output', () async {
        await open();
        final sender = await engine.openOutput(output.id);
        await engine.openOutput(umpOutput.id);
        await sender.send(const MidiNoteOn(channel: 0, note: 60, velocity: 1));
        backend.clearRecords();
        await engine.panic(
          panic: const MidiPanic(
            channels: [0],
            allSoundOff: false,
            resetAllControllers: false,
          ),
        );
        expect({
          for (final sent in backend.sent) sent.port,
        }, equals({output.id, umpOutput.id}));
        expect(
          backend.sent.firstWhere((sent) => sent.port == output.id).packet,
          bytes('80 3c 40 b0 7b 00'),
        );
      });

      test('throws for a closed engine', () async {
        engine = MidiEngine(backend: backend);
        await expectLater(engine.panic(), throwsStateError);
      });
    });

    group('hotplug', () {
      test('ends an input session after its queued events', () async {
        await open();
        final session = await engine.openInput(input.id);
        final events = session.events.toList();
        backend
          ..inject(input.id, bytes('f8'))
          ..removePort(input.id);
        expect(messagesOf(await events), equals([const MidiTimingClock()]));
        await session.done;
        await pumpEventQueue();
        expect(session.isClosed, isTrue);
        expect(engine.port(input.id), isNull);
        expect(portEvents, equals([MidiPortRemoved(port: input)]));
        expect(backend.calls, isNot(contains('closePort fake:in')));
      });

      test('needs a new open for a re-plugged port', () async {
        await open();
        final session = await engine.openInput(input.id);
        backend
          ..removePort(input.id)
          ..addPort(input);
        expect(session.isClosed, isTrue);
        final again = await engine.openInput(input.id);
        final events = <MidiEvent>[];
        again.events.listen(events.add);
        backend.inject(input.id, bytes('fa'));
        await pumpEventQueue();
        expect(messagesOf(events), equals([const MidiStart()]));
        expect([
          for (final call in backend.calls)
            if (call.startsWith('open')) call,
        ], equals(['openPort fake:in', 'openPort fake:in']));
      });

      test('ends an output session and drops its queue', () async {
        await open();
        final sender = await engine.openOutput(output.id);
        await sender.send(
          const MidiStart(),
          at: start + const Duration(milliseconds: 1),
        );
        backend.removePort(output.id);
        timers.advance(const Duration(milliseconds: 2));
        expect(backend.sent, isEmpty);
        await sender.done;
        await expectLater(
          sender.send(const MidiStop()),
          throwsA(isA<MidiPortGone>()),
        );
        await sender.close();
      });

      test('keeps a defined state when a port goes during a send', () async {
        await open();
        final sender = await engine.openOutput(output.id);
        backend.holdCalls();
        final sending = sender.send(const MidiStart());
        backend
          ..removePort(output.id)
          ..releaseCalls();
        await sending;
        expect(sender.isClosed, isTrue);
        expect(
          engine.outputs.map((port) => port.id),
          isNot(contains(output.id)),
        );
      });

      test('takes over changed ports', () async {
        await open();
        final session = await engine.openInput(input.id);
        final sender = await engine.openOutput(output.id);
        final events = <MidiEvent>[];
        session.events.listen(events.add);
        final regrouped = backend.changePort(input.copyWith(group: 5));
        final renamed = backend.changePort(output.copyWith(name: 'renamed'));
        backend.inject(input.id, bytes('f8'));
        await pumpEventQueue();
        expect(events.single.group, 5);
        expect([session.port, sender.port], equals([regrouped, renamed]));
        expect(
          portEvents,
          equals([
            MidiPortChanged(port: regrouped, previous: input),
            MidiPortChanged(port: renamed, previous: output),
          ]),
        );
      });

      test('publishes added ports', () async {
        await open();
        final added = backend.addPort(
          backend.portInfo('new', direction: MidiDirection.input),
        );
        await pumpEventQueue();
        expect(portEvents, equals([MidiPortAdded(port: added)]));
        expect(engine.inputs.last, added);
      });
    });

    group('diagnostics', () {
      test('publishes and counts the reports of the backend', () async {
        await open();
        final report = MidiDiagnostic(
          kind: MidiDiagnosticKind.networkLoss,
          port: output.id,
          count: 3,
          cause: 'lost',
          time: start,
        );
        backend.reportDiagnostic(report);
        await pumpEventQueue();
        expect(diagnostics, equals([report]));
        expect(
          engine.diagnosticsSnapshot().count(MidiDiagnosticKind.networkLoss),
          3,
        );
      });

      for (final (kind, resets) in [
        (MidiDiagnosticKind.queueOverflow, true),
        (MidiDiagnosticKind.networkLoss, true),
        (MidiDiagnosticKind.nativeError, false),
      ]) {
        test(
          '${kind.name} ${resets ? 'resets' : 'keeps'} the stream',
          () async {
            await open();
            final session = await engine.openInput(input.id);
            final events = <MidiEvent>[];
            session.events.listen(events.add);
            backend
              ..inject(input.id, bytes('f0 01'))
              ..reportDiagnostic(
                MidiDiagnostic(
                  kind: kind,
                  port: input.id,
                  cause: 'gap',
                  time: start,
                ),
              )
              ..reportDiagnostic(
                MidiDiagnostic(kind: kind, cause: 'portless', time: start),
              )
              ..inject(input.id, bytes('02 f7'));
            await pumpEventQueue();
            expect(
              messagesOf(events),
              resets
                  ? isEmpty
                  : equals([
                      MidiSysEx([0x01, 0x02]),
                    ]),
            );
          },
        );
      }
    });

    group('createVirtualPort(spec), removeVirtualPort(id)', () {
      test('create and remove own ports', () async {
        await open();
        final port = await engine.createVirtualPort(
          MidiVirtualPortSpec(name: 'Synth', direction: MidiDirection.input),
        );
        expect([port.isOwn, engine.port(port.id)], equals([true, port]));
        await engine.removeVirtualPort(port.id);
        expect(engine.port(port.id), isNull);
        await pumpEventQueue();
        expect(
          portEvents,
          equals([MidiPortAdded(port: port), MidiPortRemoved(port: port)]),
        );
      });

      test('keep the ports right when the backend reports nothing', () async {
        // The virtual ports of a backend that never started report nothing.
        final silent = FakeMidiBackend(name: 'silent');
        engine = MidiEngine(
          backend: MidiCompositeBackend(
            backends: [backend],
            virtualPorts: MidiFakeVirtualPortsBackend(backend: silent),
          ),
        );
        await engine.open();
        final port = await engine.createVirtualPort(
          MidiVirtualPortSpec(name: 'Synth', direction: MidiDirection.output),
        );
        expect(engine.port(port.id), port);
        await engine.removeVirtualPort(port.id);
        expect(engine.port(port.id), isNull);
      });

      test('throw without virtual ports or engine', () async {
        backend = FakeMidiBackend(hasVirtualPorts: false);
        engine = MidiEngine(backend: backend);
        final spec = MidiVirtualPortSpec(
          name: 'x',
          direction: MidiDirection.input,
        );
        await expectLater(engine.createVirtualPort(spec), throwsStateError);
        await engine.open();
        await expectLater(
          engine.createVirtualPort(spec),
          throwsA(isA<MidiUnsupported>()),
        );
        await expectLater(
          engine.removeVirtualPort(const MidiPortId('fake:x')),
          throwsA(isA<MidiUnsupported>()),
        );
      });
    });

    group('replugCandidates(port), devices', () {
      test('find ports with the same fingerprint and group devices', () async {
        const device = MidiDeviceId('fake:keys');
        final keys = backend.addPort(
          backend.portInfo(
            'keys',
            direction: MidiDirection.input,
            deviceId: device,
            serialNumber: '42',
          ),
        );
        await open();
        final replugged = backend.addPort(
          backend.portInfo(
            'keys2',
            name: 'keys',
            direction: MidiDirection.input,
            serialNumber: '42',
          ),
        );
        expect(engine.replugCandidates(keys), equals([replugged]));
        expect(engine.devices.single.ports, equals([keys.id]));
      });
    });
  });
}
