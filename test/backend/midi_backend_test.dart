// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// The smallest backend: it logs every call.
final class _LoggingBackend implements MidiBackend {
  final log = <String>[];

  @override
  Future<void> start(MidiBackendHost host) async => log.add('start');

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Future<void> openPort(MidiPortId port) async => log.add('open $port');

  @override
  Future<void> closePort(MidiPortId port) async => log.add('close $port');

  @override
  Future<void> send(MidiPortId port, MidiPacket packet) async =>
      log.add('send $port ${packet.time.microseconds}');

  @override
  Future<void> cancelPending(MidiPortId port) async => log.add('cancel $port');

  @override
  String get name => 'logging';

  @override
  MidiCapabilities get capabilities => const MidiCapabilities.none();

  @override
  List<MidiPortInfo> get ports => const [];

  @override
  MidiVirtualPortsBackend? get virtualPorts => null;

  @override
  MidiBluetoothBackend? get bluetooth => null;

  @override
  MidiNetworkBackend? get network => null;
}

/// A host that ignores everything.
final class _SilentHost implements MidiBackendHost {
  @override
  MidiClock get clock => MidiFakeClock();

  @override
  void portsChanged(List<MidiPortEvent> events) {}

  @override
  void received(MidiPortId port, MidiPacket packet) {}

  @override
  void diagnostic(MidiDiagnostic diagnostic) {}
}

void main() {
  group('MidiBackend', () {
    test('is implemented by the backends of the package', () {
      expect(FakeMidiBackend(), isA<MidiBackend>());
      expect(MidiCompositeBackend(backends: const []), isA<MidiBackend>());
    });

    test('runs an implementation through the whole contract', () async {
      final logging = _LoggingBackend();
      final MidiBackend backend = logging;
      const port = MidiPortId('logging:out');
      await backend.start(_SilentHost());
      await backend.openPort(port);
      await backend.send(
        port,
        MidiBytesPacket(bytes: MidiBytes([0xF8]), time: const MidiTime(9)),
      );
      await backend.cancelPending(port);
      await backend.closePort(port);
      await backend.stop();
      expect(
        logging.log,
        equals([
          'start',
          'open logging:out',
          'send logging:out 9',
          'cancel logging:out',
          'close logging:out',
          'stop',
        ]),
      );
      expect(backend.name, 'logging');
      expect(backend.capabilities, const MidiCapabilities.none());
      expect(backend.ports, isEmpty);
      expect([
        backend.virtualPorts,
        backend.bluetooth,
        backend.network,
      ], equals([null, null, null]));
    });
  });
}
