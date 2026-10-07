// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A host that records what the backend reports.
final class _RecordingHost implements MidiBackendHost {
  final events = <MidiPortEvent>[];
  final packets = <(MidiPortId, MidiPacket)>[];
  final diagnostics = <MidiDiagnostic>[];

  @override
  final MidiFakeClock clock = MidiFakeClock(start: const MidiTime(100));

  @override
  void portsChanged(List<MidiPortEvent> events) => this.events.addAll(events);

  @override
  void received(MidiPortId port, MidiPacket packet) =>
      packets.add((port, packet));

  @override
  void diagnostic(MidiDiagnostic diagnostic) => diagnostics.add(diagnostic);
}

void main() {
  late _RecordingHost host;
  late FakeMidiBackend backend;
  late MidiPortInfo input;
  late MidiPortInfo output;

  // A bytes packet of [hex] due at [micros].
  MidiPacket bytes(String hex, [int micros = 100]) =>
      MidiBytesPacket(bytes: MidiBytes.fromHex(hex), time: MidiTime(micros));

  // Starts the backend and opens [ports].
  Future<void> startWith(List<MidiPortInfo> ports) async {
    await backend.start(host);
    for (final port in ports) {
      await backend.openPort(port.id);
    }
  }

  setUp(() {
    host = _RecordingHost();
    backend = FakeMidiBackend();
    input = backend.addPort(
      backend.portInfo('in', direction: MidiDirection.input),
    );
    output = backend.addPort(
      backend.portInfo('out', direction: MidiDirection.output),
    );
    backend.connectLoopback(output.id, input.id);
  });

  group('FakeMidiBackend', () {
    group('FakeMidiBackend(...)', () {
      test('offers every sub-API by default', () {
        final fake = FakeMidiBackend(ports: [input]);
        expect(fake.name, 'fake');
        expect(fake.ports, equals([input]));
        expect(
          fake.capabilities,
          MidiCapabilities(
            virtualPorts: MidiVirtualPortSupport.dynamicPorts,
            bleScan: true,
            network: {MidiNetworkSupport.appleMidi},
            ump: true,
          ),
        );
        expect(fake.virtualPorts!.backend, same(fake));
        expect(fake.bluetooth!.backend, same(fake));
        expect(fake.network!.backend, same(fake));
        expect(fake.timerFactory, isNotNull);
      });

      test('leaves out the sub-APIs it is told to', () {
        final fake = FakeMidiBackend(
          name: 'bare',
          hasVirtualPorts: false,
          hasBluetooth: false,
          hasNetwork: false,
        );
        expect(
          [fake.virtualPorts, fake.bluetooth, fake.network],
          [null, null, null],
        );
        expect(fake.capabilities, MidiCapabilities(ump: true));
      });

      test('takes given capabilities', () {
        final capabilities = MidiCapabilities(blePeripheral: true);
        expect(
          FakeMidiBackend(capabilities: capabilities).capabilities,
          same(capabilities),
        );
      });
    });

    group('start(host), stop()', () {
      test('run the backend once at a time', () async {
        await backend.start(host);
        expect([backend.isStarted, backend.host], [true, host]);
        await expectLater(
          backend.start(host),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'The backend runs already',
            ),
          ),
        );
        await backend.openPort(input.id);
        await backend.stop();
        expect([backend.isStarted, backend.openPorts], [false, isEmpty]);
        expect(backend.calls, ['start', 'start', 'openPort fake:in', 'stop']);
      });
    });

    group('openPort(port), closePort(port)', () {
      test('open and close ports', () async {
        await startWith([input]);
        expect(backend.openPorts, equals({input.id}));
        await backend.closePort(input.id);
        await backend.closePort(input.id);
        await backend.closePort(const MidiPortId('fake:none'));
        expect(backend.openPorts, isEmpty);
        await expectLater(
          backend.openPort(const MidiPortId('fake:none')),
          throwsA(isA<MidiPortGone>()),
        );
        expect(() => backend.openPorts.clear(), throwsUnsupportedError);
      });
    });

    group('send(port, packet)', () {
      test('records the packet and loops it back', () async {
        await startWith([input, output]);
        await backend.send(output.id, bytes('f8', 50));
        await backend.send(output.id, bytes('fa', 300));
        expect(
          backend.sent,
          equals([
            (
              port: output.id,
              packet: bytes('f8', 50),
              sentAt: const MidiTime(100),
            ),
            (
              port: output.id,
              packet: bytes('fa', 300),
              sentAt: const MidiTime(100),
            ),
          ]),
        );
        expect(
          host.packets,
          equals([(input.id, bytes('f8', 100)), (input.id, bytes('fa', 300))]),
        );
      });

      test('loops back to open inputs only', () async {
        await startWith([output]);
        await backend.send(output.id, bytes('f8'));
        backend.disconnectLoopback(output.id, input.id);
        await backend.openPort(input.id);
        await backend.send(output.id, bytes('f8'));
        backend.disconnectLoopback(input.id, output.id);
        expect(host.packets, isEmpty);
      });

      test('throws for wrong ports, forms and states', () async {
        final ump = backend.addPort(
          backend.portInfo(
            'ump',
            direction: MidiDirection.output,
            capabilities: const MidiPortCapabilities(ump: true),
          ),
        );
        await expectLater(
          backend.send(output.id, bytes('f8')),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'fake:out is not open',
            ),
          ),
        );
        await startWith([input, output, ump]);
        await expectLater(
          backend.send(const MidiPortId('fake:none'), bytes('f8')),
          throwsA(isA<MidiPortGone>()),
        );
        await expectLater(
          backend.send(input.id, bytes('f8')),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          backend.send(ump.id, bytes('f8')),
          throwsA(
            isA<MidiUnsupported>().having(
              (e) => e.feature,
              'feature',
              'MidiBytesPacket on fake:ump',
            ),
          ),
        );
        await expectLater(
          backend.send(
            output.id,
            MidiUmpPacket(words: const [0x10F80000], time: MidiTime.zero),
          ),
          throwsA(isA<MidiUnsupported>()),
        );
      });
    });

    group('cancelPending(port)', () {
      test('records the call for outputs', () async {
        await backend.cancelPending(output.id);
        expect(backend.calls, equals(['cancelPending fake:out']));
        await expectLater(
          backend.cancelPending(input.id),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          backend.cancelPending(const MidiPortId('fake:none')),
          throwsA(isA<MidiPortGone>()),
        );
      });
    });

    group('portInfo(nativeId, ...)', () {
      test('describes a port of the backend', () {
        const device = MidiDeviceId('fake:device');
        final port = backend.portInfo(
          'x',
          direction: MidiDirection.output,
          name: 'X',
          manufacturer: 'Maker',
          index: 2,
          transport: MidiTransport.usb,
          protocol: MidiProtocol.midi2,
          group: 3,
          capabilities: const MidiPortCapabilities(ump: true),
          deviceId: device,
          serialNumber: '7',
        );
        expect(
          port,
          MidiPortInfo(
            id: const MidiPortId('fake:x'),
            deviceId: device,
            name: 'X',
            manufacturer: 'Maker',
            direction: MidiDirection.output,
            index: 2,
            transport: MidiTransport.usb,
            protocol: MidiProtocol.midi2,
            group: 3,
            capabilities: const MidiPortCapabilities(ump: true),
            serialNumber: '7',
          ),
        );
        expect(backend.portInfo('y', direction: MidiDirection.input).name, 'y');
      });
    });

    group('addPort(port), changePort(port), removePort(id)', () {
      test('report hotplug while the backend runs', () async {
        await startWith([input]);
        final extra = backend.addPort(
          backend.portInfo('extra', direction: MidiDirection.input),
        );
        final renamed = backend.changePort(extra.copyWith(name: 'renamed'));
        final again = backend.addPort(renamed.copyWith(name: 'again'));
        backend.removePort(input.id);
        expect(
          host.events,
          equals([
            MidiPortAdded(port: extra),
            MidiPortChanged(port: renamed, previous: extra),
            MidiPortChanged(port: again, previous: renamed),
            MidiPortRemoved(port: input),
          ]),
        );
        expect(backend.port(input.id), isNull);
        expect(backend.openPorts, isEmpty);
        expect(backend.ports, equals([output, again]));
      });

      test('drop the loopbacks of a removed port', () async {
        backend
          ..removePort(input.id)
          ..addPort(input);
        await startWith([input, output]);
        await backend.send(output.id, bytes('f8'));
        expect(host.packets, isEmpty);
      });

      test('drop the loopbacks to a removed input', () async {
        final second = backend.addPort(
          backend.portInfo('second', direction: MidiDirection.input),
        );
        backend
          ..connectLoopback(output.id, second.id)
          ..removePort(second.id);
        await startWith([input, output]);
        await backend.send(output.id, bytes('f8'));
        expect(host.packets.single.$1, input.id);
      });

      test('throw for unknown ports', () {
        expect(
          () => backend.removePort(const MidiPortId('fake:none')),
          throwsA(isA<MidiPortGone>()),
        );
        expect(
          () => backend.changePort(
            backend.portInfo('none', direction: MidiDirection.input),
          ),
          throwsA(isA<MidiPortGone>()),
        );
      });
    });

    group('connectLoopback(output, input)', () {
      test('needs an output, an input and one raw form', () {
        final ump = backend.addPort(
          backend.portInfo(
            'ump',
            direction: MidiDirection.input,
            capabilities: const MidiPortCapabilities(ump: true),
          ),
        );
        expect(
          () => backend.connectLoopback(input.id, output.id),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'A loopback runs from an output to an input',
            ),
          ),
        );
        expect(
          () => backend.connectLoopback(output.id, ump.id),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'A loopback needs ports of the same raw form',
            ),
          ),
        );
        expect(
          () => backend.connectLoopback(output.id, const MidiPortId('fake:x')),
          throwsA(isA<MidiPortGone>()),
        );
      });
    });

    group('inject(port, packet), reportDiagnostic(diagnostic)', () {
      test('reach the host while the backend runs', () async {
        expect(backend.inject(input.id, bytes('f8')), isFalse);
        const diagnostic = MidiDiagnostic(
          kind: MidiDiagnosticKind.networkLoss,
          cause: 'lost',
          time: MidiTime.zero,
        );
        backend.reportDiagnostic(diagnostic);
        await backend.start(host);
        expect(backend.inject(input.id, bytes('f8')), isFalse);
        await backend.openPort(input.id);
        expect(backend.inject(input.id, bytes('f8')), isTrue);
        backend.reportDiagnostic(diagnostic);
        expect(host.packets, equals([(input.id, bytes('f8'))]));
        expect(host.diagnostics, equals([diagnostic]));
      });
    });

    group('failWith(...)', () {
      test('makes the calls throw until replaced', () async {
        final error = StateError('broken');
        backend.failWith(
          start: error,
          stop: error,
          openPort: error,
          closePort: error,
          send: error,
          cancelPending: error,
        );
        for (final call in <Future<void> Function()>[
          () => backend.start(host),
          backend.stop,
          () => backend.openPort(input.id),
          () => backend.closePort(input.id),
          () => backend.send(output.id, bytes('f8')),
          () => backend.cancelPending(output.id),
        ]) {
          await expectLater(call(), throwsA(same(error)));
        }
        backend.failWith();
        await backend.start(host);
        expect(backend.isStarted, isTrue);
      });
    });

    group('holdCalls(), releaseCalls()', () {
      test('keep the calls pending while they take effect', () async {
        await startWith([input, output]);
        backend.holdCalls();
        var completed = 0;
        for (final call in <Future<void> Function()>[
          () => backend.openPort(input.id),
          () => backend.send(output.id, bytes('f8')),
          () => backend.cancelPending(output.id),
          () => backend.closePort(input.id),
          backend.stop,
          () => backend.start(host),
        ]) {
          unawaited(call().then((_) => completed++));
        }
        await pumpEventQueue();
        expect(completed, 0);
        expect(backend.sent, hasLength(1));
        backend
          ..releaseCalls()
          ..releaseCalls();
        await pumpEventQueue();
        expect(completed, 6);
      });
    });

    group('clearRecords()', () {
      test('forgets the sent packets and calls', () async {
        await startWith([output]);
        await backend.send(output.id, bytes('f8'));
        backend.clearRecords();
        expect([backend.sent, backend.calls], [isEmpty, isEmpty]);
        expect(() => backend.sent.clear(), throwsUnsupportedError);
        expect(() => backend.calls.clear(), throwsUnsupportedError);
      });
    });
  });
}
