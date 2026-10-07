// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:typed_data';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A GATT connection in memory: notifications are pushed by the test,
/// writes are recorded.
final class _FakeConnection implements MidiBleConnection {
  _FakeConnection(this.peripheralId);

  final incoming = StreamController<Uint8List>();
  final ended = Completer<void>();
  final written = <List<int>>[];
  Completer<void>? writeGate;
  Object? writeError;
  bool isDisconnected = false;

  @override
  Future<void> write(Uint8List packet) async {
    await writeGate?.future;
    final error = writeError;
    if (error != null) throw error;
    written.add(packet);
  }

  @override
  Future<void> disconnect() async {
    isDisconnected = true;
    if (!ended.isCompleted) ended.complete();
  }

  @override
  final String peripheralId;

  @override
  Stream<Uint8List> get notifications => incoming.stream;

  @override
  int get maxPacketLength => 8;

  @override
  Future<void> get done => ended.future;
}

/// A GATT client in memory.
final class _FakeTransport implements MidiBleTransport {
  final found = <MidiBlePeripheralInfo>[];
  final connections = <String, _FakeConnection>{};
  final log = <String>[];
  Completer<void>? connectGate;

  @override
  Stream<MidiBlePeripheralInfo> scan({Duration? timeout}) {
    log.add('scan $timeout');
    return Stream.fromIterable(found);
  }

  @override
  Future<void> stopScan() async => log.add('stopScan');

  @override
  Future<MidiBleConnection> connect(
    String peripheralId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    log.add('connect $peripheralId $timeout');
    await connectGate?.future;
    return connections[peripheralId] = _FakeConnection(peripheralId);
  }
}

/// A host that records what the backend reports.
final class _RecordingHost implements MidiBackendHost {
  final events = <MidiPortEvent>[];
  final packets = <(MidiPortId, MidiPacket)>[];
  final diagnostics = <MidiDiagnostic>[];

  @override
  final MidiFakeClock clock = MidiFakeClock(start: const MidiTime(1000000));

  @override
  void portsChanged(List<MidiPortEvent> events) => this.events.addAll(events);

  @override
  void received(MidiPortId port, MidiPacket packet) =>
      packets.add((port, packet));

  @override
  void diagnostic(MidiDiagnostic diagnostic) => diagnostics.add(diagnostic);
}

void main() {
  const inputId = MidiPortId('ble:AA:BB/input');
  const outputId = MidiPortId('ble:AA:BB/output');
  late _FakeTransport transport;
  late _RecordingHost host;
  late MidiBleBluetoothBackend backend;

  // The BLE-MIDI packets of [messages], each due at its time.
  List<Uint8List> ble(List<MidiTimedMessage> messages) =>
      MidiBleEncoder(maxPacketLength: 8).encode(messages);

  // Starts the backend and connects the peripheral AA:BB.
  Future<_FakeConnection> connected() async {
    await backend.start(host);
    await backend.connect('AA:BB');
    return transport.connections['AA:BB']!;
  }

  setUp(() {
    transport = _FakeTransport();
    host = _RecordingHost();
    backend = MidiBleBluetoothBackend(transport: transport);
  });

  group('MidiBleBluetoothBackend', () {
    group('MidiBleBluetoothBackend({transport, name, maxSysExLength})', () {
      test('is a BLE-MIDI central without other sub-APIs', () {
        expect(backend.transport, same(transport));
        expect([backend.name, backend.maxSysExLength], ['ble', 1 << 20]);
        expect(backend.capabilities, MidiCapabilities(bleScan: true));
        expect(backend.bluetooth, same(backend));
        expect([backend.virtualPorts, backend.network], [null, null]);
        expect(backend.ports, isEmpty);
      });
    });

    group('start(host), stop()', () {
      test('run once at a time and disconnect silently', () async {
        final connection = await connected();
        await expectLater(backend.start(host), throwsStateError);
        host.events.clear();
        await backend.stop();
        expect(connection.isDisconnected, isTrue);
        expect(backend.ports, isEmpty);
        expect(host.events, isEmpty);
        await backend.start(host);
      });
    });

    group('scan({timeout}), stopScan()', () {
      test('pass through and name the ports after the finding', () async {
        transport.found.addAll([
          MidiBlePeripheralInfo(id: 'AA:BB', name: 'Keys'),
          MidiBlePeripheralInfo(id: 'CC:DD'),
        ]);
        final found = await backend
            .scan(timeout: const Duration(seconds: 3))
            .toList();
        await backend.stopScan();
        expect(found, equals(transport.found));
        expect(transport.log, ['scan 0:00:03.000000', 'stopScan']);
        await backend.start(host);
        final keys = await backend.connect('AA:BB');
        final unnamed = await backend.connect('CC:DD');
        expect([keys.first.name, unnamed.first.name], ['Keys', 'CC:DD']);
      });
    });

    group('connect(peripheralId, {timeout})', () {
      test('adds an input and an output port', () async {
        await backend.start(host);
        final ports = await backend.connect(
          'AA:BB',
          timeout: const Duration(seconds: 2),
        );
        const device = MidiDeviceId('ble:AA:BB');
        final expected = [
          for (final (id, direction) in [
            (inputId, MidiDirection.input),
            (outputId, MidiDirection.output),
          ])
            MidiPortInfo(
              id: id,
              deviceId: device,
              name: 'AA:BB',
              direction: direction,
              transport: MidiTransport.bluetoothLe,
              capabilities: const MidiPortCapabilities(timestampsIn: true),
              serialNumber: 'AA:BB',
            ),
        ];
        expect(ports, equals(expected));
        expect(backend.ports, equals(expected));
        expect(
          host.events,
          equals([for (final port in expected) MidiPortAdded(port: port)]),
        );
        expect(transport.log, ['connect AA:BB 0:00:02.000000']);
        expect(await backend.connect('AA:BB'), equals(expected));
      });

      test('shares a connection in progress', () async {
        await backend.start(host);
        final first = backend.connect('AA:BB');
        final second = backend.connect('AA:BB');
        expect(await first, equals(await second));
        expect(transport.log, hasLength(1));
      });

      test('needs a started backend', () async {
        await expectLater(
          backend.connect('AA:BB'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'The backend is not started',
            ),
          ),
        );
      });

      test('fails when the backend stops while connecting', () async {
        await backend.start(host);
        transport.connectGate = Completer<void>();
        final connecting = backend.connect('AA:BB');
        await pumpEventQueue();
        await backend.stop();
        transport.connectGate!.complete();
        await expectLater(connecting, throwsStateError);
        expect(transport.connections['AA:BB']!.isDisconnected, isTrue);
        expect(backend.ports, isEmpty);
      });
    });

    group('notifications', () {
      test('arrive as bytes packets with their times when open', () async {
        final connection = await connected();
        final now = host.clock.now();
        final packets = ble([
          (
            message: const MidiNoteOn(channel: 0, note: 60, velocity: 100),
            time: MidiTime.zero,
          ),
          (message: const MidiTimingClock(), time: const MidiTime(5000)),
        ]);
        connection.incoming.add(packets.single);
        await pumpEventQueue();
        expect(host.packets, isEmpty);
        await backend.openPort(inputId);
        connection.incoming.add(packets.single);
        await pumpEventQueue();
        expect(
          host.packets,
          equals([
            (
              inputId,
              MidiBytesPacket(
                bytes: MidiBytes.fromHex('90 3c 64'),
                time: now - const Duration(milliseconds: 5),
              ),
            ),
            (inputId, MidiBytesPacket(bytes: MidiBytes([0xF8]), time: now)),
          ]),
        );
        await backend.closePort(inputId);
        connection.incoming.add(packets.single);
        await pumpEventQueue();
        expect(host.packets, hasLength(2));
      });

      test('report malformed packets for the input', () async {
        final connection = await connected();
        await backend.openPort(inputId);
        connection.incoming.add(Uint8List.fromList([0x00]));
        await pumpEventQueue();
        expect(
          host.diagnostics,
          equals([
            MidiDiagnostic(
              kind: MidiDiagnosticKind.invalidData,
              port: inputId,
              cause: 'BLE-MIDI packet without header byte',
              time: host.clock.now(),
            ),
          ]),
        );
      });

      test('reassemble System Exclusive across packets', () async {
        final connection = await connected();
        await backend.openPort(inputId);
        final sysEx = MidiSysEx(List.generate(12, (i) => i));
        final packets = ble([(message: sysEx, time: MidiTime.zero)]);
        expect(packets.length, greaterThan(1));
        packets.forEach(connection.incoming.add);
        await pumpEventQueue();
        expect(
          (host.packets.single.$2 as MidiBytesPacket).bytes,
          sysEx.toBytes(),
        );
      });
    });

    group('openPort(port), closePort(port)', () {
      test('open known ports and close any port', () async {
        await connected();
        await backend.openPort(outputId);
        await backend.closePort(outputId);
        await backend.closePort(const MidiPortId('ble:none'));
        await expectLater(
          backend.openPort(const MidiPortId('ble:none')),
          throwsA(isA<MidiPortGone>()),
        );
      });
    });

    group('send(port, packet)', () {
      test('writes BLE-MIDI packets in order', () async {
        final connection = await connected();
        final now = host.clock.now();
        final gate = connection.writeGate = Completer<void>();
        final first = backend.send(
          outputId,
          MidiBytesPacket(bytes: MidiBytes.fromHex('90 3c 64'), time: now),
        );
        final sysEx = MidiSysEx(List.generate(12, (i) => i));
        final second = backend.send(
          outputId,
          MidiBytesPacket(bytes: sysEx.toBytes()!, time: now),
        );
        gate.complete();
        await Future.wait([first, second]);
        expect(
          connection.written,
          equals([
            ...ble([
              (
                message: const MidiNoteOn(channel: 0, note: 60, velocity: 100),
                time: now,
              ),
            ]),
            ...ble([(message: sysEx, time: now)]),
          ]),
        );
      });

      test('passes write failures on and keeps writing', () async {
        final connection = await connected();
        connection.writeError = StateError('link lost');
        final packet = MidiBytesPacket(
          bytes: MidiBytes([0xF8]),
          time: MidiTime.zero,
        );
        await expectLater(backend.send(outputId, packet), throwsStateError);
        connection.writeError = null;
        await backend.send(outputId, packet);
        expect(connection.written, hasLength(1));
      });

      test('throws for unknown ports, inputs and UMP', () async {
        await connected();
        final packet = MidiBytesPacket(
          bytes: MidiBytes([0xF8]),
          time: MidiTime.zero,
        );
        await expectLater(
          backend.send(const MidiPortId('ble:none'), packet),
          throwsA(isA<MidiPortGone>()),
        );
        await expectLater(
          backend.send(inputId, packet),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          backend.send(
            outputId,
            MidiUmpPacket(words: const [0x10F80000], time: MidiTime.zero),
          ),
          throwsA(isA<MidiUnsupported>()),
        );
      });
    });

    group('cancelPending(port)', () {
      test('holds nothing to discard', () async {
        await connected();
        await backend.cancelPending(outputId);
        await expectLater(
          backend.cancelPending(inputId),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          backend.cancelPending(const MidiPortId('ble:none')),
          throwsA(isA<MidiPortGone>()),
        );
      });
    });

    group('disconnect(peripheralId)', () {
      test('removes the ports once', () async {
        final connection = await connected();
        host.events.clear();
        await backend.disconnect('AA:BB');
        await backend.disconnect('AA:BB');
        await pumpEventQueue();
        expect(connection.isDisconnected, isTrue);
        expect(host.events.map((event) => event.runtimeType), [
          MidiPortRemoved,
          MidiPortRemoved,
        ]);
        expect(backend.ports, isEmpty);
      });
    });

    group('connection loss', () {
      for (final failed in [false, true]) {
        test(
          'removes the ports when done ${failed ? 'fails' : 'completes'}',
          () async {
            final connection = await connected();
            host.events.clear();
            failed
                ? connection.ended.completeError(StateError('gone'))
                : connection.ended.complete();
            await pumpEventQueue();
            expect(host.events, hasLength(2));
            expect(backend.ports, isEmpty);
          },
        );
      }
    });

    group('in an engine', () {
      test('delivers events and sends through the GATT link', () async {
        final engine = MidiEngine(backend: backend, clock: host.clock);
        await engine.open();
        final ports = await engine.bluetooth!.connect('AA:BB');
        final connection = transport.connections['AA:BB']!;
        final input = await engine.openInput(ports.first.id);
        final events = <MidiEvent>[];
        input.events.listen(events.add);
        final output = await engine.openOutput(ports.last.id);
        connection.incoming.add(
          ble([(message: const MidiStart(), time: MidiTime.zero)]).single,
        );
        await output.send(const MidiStop());
        await pumpEventQueue();
        expect(events.single.message, const MidiStart());
        expect(events.single.port, inputId);
        expect(connection.written, hasLength(1));
        await engine.close();
        expect(connection.isDisconnected, isTrue);
      });
    });
  });
}
