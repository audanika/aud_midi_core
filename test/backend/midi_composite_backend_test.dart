// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A host that records the diagnostics of the backends.
final class _RecordingHost implements MidiBackendHost {
  final diagnostics = <MidiDiagnostic>[];

  @override
  final MidiClock clock = MidiFakeClock(start: const MidiTime(3));

  @override
  void portsChanged(List<MidiPortEvent> events) {}

  @override
  void received(MidiPortId port, MidiPacket packet) {}

  @override
  void diagnostic(MidiDiagnostic diagnostic) => diagnostics.add(diagnostic);
}

void main() {
  late _RecordingHost host;
  late FakeMidiBackend os;
  late FakeMidiBackend network;
  late FakeMidiBackend ble;
  late MidiPortInfo osOut;
  late MidiPortInfo networkOut;

  setUp(() {
    host = _RecordingHost();
    os = FakeMidiBackend(name: 'os', hasBluetooth: false, hasNetwork: false);
    network = FakeMidiBackend(
      name: 'net',
      hasVirtualPorts: false,
      hasBluetooth: false,
    );
    ble = FakeMidiBackend(name: 'ble', hasVirtualPorts: false);
    osOut = os.addPort(os.portInfo('out', direction: MidiDirection.output));
    networkOut = network.addPort(
      network.portInfo('out', direction: MidiDirection.output),
    );
  });

  group('MidiCompositeBackend', () {
    group('MidiCompositeBackend(...)', () {
      test('keeps the backends', () {
        final composite = MidiCompositeBackend(
          backends: [os],
          optionalBackends: [ble],
        );
        expect(composite.name, 'composite');
        expect(
          [composite.backends, composite.optionalBackends],
          [
            [os],
            [ble],
          ],
        );
        expect(composite.activeBackends, equals([os, ble]));
        expect(() => composite.backends.clear(), throwsUnsupportedError);
      });

      test('rejects backends with the same name', () {
        expect(
          () => MidiCompositeBackend(
            backends: [os],
            optionalBackends: [FakeMidiBackend(name: 'os')],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Two backends share the name',
            ),
          ),
        );
      });
    });

    group('start(host)', () {
      test('starts the backends in order', () async {
        final composite = MidiCompositeBackend(
          backends: [os, network],
          optionalBackends: [ble],
        );
        await composite.start(host);
        expect([os.host, network.host, ble.host], everyElement(same(host)));
        expect(composite.ports, equals([osOut, networkOut]));
        await expectLater(composite.start(host), throwsStateError);
      });

      test('stops the started ones when a required one fails', () async {
        network.failWith(start: StateError('no socket'));
        final composite = MidiCompositeBackend(backends: [os, network]);
        await expectLater(
          composite.start(host),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'no socket'),
          ),
        );
        expect(
          [os.isStarted, os.calls],
          equals([
            false,
            ['start', 'stop'],
          ]),
        );
        expect(composite.ports, isEmpty);
        network.failWith();
        await composite.start(host);
        expect(os.isStarted, isTrue);
      });

      test('leaves out an optional backend that fails', () async {
        ble.failWith(start: StateError('no bluetooth'));
        final composite = MidiCompositeBackend(
          backends: [os],
          optionalBackends: [ble],
        );
        await composite.start(host);
        expect(composite.activeBackends, equals([os]));
        expect(
          host.diagnostics,
          equals([
            const MidiDiagnostic(
              kind: MidiDiagnosticKind.nativeError,
              cause: 'Backend ble failed to start: Bad state: no bluetooth',
              time: MidiTime(3),
            ),
          ]),
        );
        expect(composite.bluetooth, isNull);
      });
    });

    group('stop()', () {
      test('stops in reverse order and rethrows the first failure', () async {
        final composite = MidiCompositeBackend(backends: [os, network, ble]);
        await composite.start(host);
        network.failWith(stop: StateError('network'));
        os.failWith(stop: StateError('os'));
        await expectLater(
          composite.stop(),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'network'),
          ),
        );
        expect(
          [ble.calls.last, network.calls.last, os.calls.last],
          ['stop', 'stop', 'stop'],
        );
        expect(ble.isStarted, isFalse);
        expect(composite.ports, isEmpty);
      });
    });

    group('openPort, closePort, send, cancelPending', () {
      test('go to the backend named by the port id', () async {
        final composite = MidiCompositeBackend(backends: [os, network]);
        await composite.start(host);
        await composite.openPort(networkOut.id);
        await composite.send(
          networkOut.id,
          MidiBytesPacket(bytes: MidiBytes([0xF8]), time: MidiTime.zero),
        );
        await composite.cancelPending(networkOut.id);
        await composite.closePort(networkOut.id);
        expect(
          network.calls,
          equals([
            'start',
            'openPort net:out',
            'send net:out',
            'cancelPending net:out',
            'closePort net:out',
          ]),
        );
        expect(os.calls, equals(['start']));
      });

      test('treat ports of unknown backends as gone', () async {
        final composite = MidiCompositeBackend(backends: [os]);
        await composite.start(host);
        const unknown = MidiPortId('webmidi:output:1');
        for (final call in <Future<void> Function()>[
          () => composite.openPort(unknown),
          () => composite.cancelPending(unknown),
          () => composite.send(
            unknown,
            MidiBytesPacket(bytes: MidiBytes([0xF8]), time: MidiTime.zero),
          ),
        ]) {
          await expectLater(call(), throwsA(isA<MidiPortGone>()));
        }
        await composite.closePort(unknown);
        expect(os.calls, equals(['start']));
      });
    });

    group('capabilities', () {
      test('are none without backends', () {
        expect(
          MidiCompositeBackend(backends: const []).capabilities,
          const MidiCapabilities.none(),
        );
      });

      test('merge the capabilities of the backends', () {
        final staticPorts = FakeMidiBackend(
          name: 'static',
          capabilities: MidiCapabilities(
            virtualPorts: MidiVirtualPortSupport.staticPorts,
            scheduling: MidiSchedulingSupport.hardware,
            network: {MidiNetworkSupport.networkMidi2},
            missingPermissions: {MidiPermission.bluetooth},
          ),
        );
        final hardware = FakeMidiBackend(
          name: 'hardware',
          capabilities: MidiCapabilities(
            blePeripheral: true,
            scheduling: MidiSchedulingSupport.hardware,
            missingPermissions: {MidiPermission.localNetwork},
          ),
        );
        expect(
          MidiCompositeBackend(backends: [staticPorts, hardware]).capabilities,
          MidiCapabilities(
            virtualPorts: MidiVirtualPortSupport.staticPorts,
            blePeripheral: true,
            network: {MidiNetworkSupport.networkMidi2},
            scheduling: MidiSchedulingSupport.hardware,
            missingPermissions: {
              MidiPermission.bluetooth,
              MidiPermission.localNetwork,
            },
          ),
        );
        expect(
          MidiCompositeBackend(backends: [staticPorts, os, ble]).capabilities,
          MidiCapabilities(
            virtualPorts: MidiVirtualPortSupport.dynamicPorts,
            bleScan: true,
            network: {
              MidiNetworkSupport.networkMidi2,
              MidiNetworkSupport.appleMidi,
            },
            ump: true,
            missingPermissions: {MidiPermission.bluetooth},
          ),
        );
      });
    });

    group('virtualPorts, bluetooth, network', () {
      test('are the first ones the backends offer', () {
        final composite = MidiCompositeBackend(backends: [network, os, ble]);
        expect(composite.virtualPorts, same(os.virtualPorts));
        expect(composite.bluetooth, same(ble.bluetooth));
        expect(composite.network, same(network.network));
        final none = MidiCompositeBackend(
          backends: [
            FakeMidiBackend(
              hasVirtualPorts: false,
              hasBluetooth: false,
              hasNetwork: false,
            ),
          ],
        );
        expect(
          [none.virtualPorts, none.bluetooth, none.network],
          [null, null, null],
        );
      });

      test('are the ones given to the constructor', () {
        final other = FakeMidiBackend(name: 'other');
        final composite = MidiCompositeBackend(
          backends: [os, network, ble],
          virtualPorts: other.virtualPorts,
          bluetooth: other.bluetooth,
          network: other.network,
        );
        expect(composite.virtualPorts, same(other.virtualPorts));
        expect(composite.bluetooth, same(other.bluetooth));
        expect(composite.network, same(other.network));
      });
    });
  });
}
