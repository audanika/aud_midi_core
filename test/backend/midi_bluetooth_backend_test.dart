// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A central that knows one peripheral and connects it without ports.
final class _OnePeripheral implements MidiBluetoothBackend {
  final log = <String>[];

  @override
  Stream<MidiBlePeripheralInfo> scan({Duration? timeout}) {
    log.add('scan $timeout');
    return Stream.value(MidiBlePeripheralInfo(id: 'p1', name: 'Keys'));
  }

  @override
  Future<void> stopScan() async => log.add('stopScan');

  @override
  Future<List<MidiPortInfo>> connect(
    String peripheralId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    log.add('connect $peripheralId $timeout');
    return const [];
  }

  @override
  Future<void> disconnect(String peripheralId) async =>
      log.add('disconnect $peripheralId');
}

void main() {
  group('MidiBluetoothBackend', () {
    test('is implemented by the package', () {
      final backend = FakeMidiBackend();
      expect(backend.bluetooth, isA<MidiBluetoothBackend>());
    });

    test('runs an implementation through the whole contract', () async {
      final central = _OnePeripheral();
      final MidiBluetoothBackend bluetooth = central;
      final found = await bluetooth
          .scan(timeout: const Duration(seconds: 1))
          .toList();
      await bluetooth.stopScan();
      final ports = await bluetooth.connect('p1');
      await bluetooth.disconnect('p1');
      expect(found, equals([MidiBlePeripheralInfo(id: 'p1', name: 'Keys')]));
      expect(ports, isEmpty);
      expect(
        central.log,
        equals([
          'scan 0:00:01.000000',
          'stopScan',
          'connect p1 0:00:10.000000',
          'disconnect p1',
        ]),
      );
    });
  });
}
