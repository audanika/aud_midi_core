// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  late MidiFakeClock clock;
  late MidiFakeTimers timers;
  late FakeMidiBackend backend;
  late MidiFakeBluetoothBackend bluetooth;
  late MidiBlePeripheralInfo keys;

  setUp(() {
    clock = MidiFakeClock();
    timers = MidiFakeTimers(clock: clock);
    backend = FakeMidiBackend(timerFactory: timers.create);
    bluetooth = backend.bluetooth!;
    keys = MidiBlePeripheralInfo(id: 'AA:BB', name: 'Keys', rssi: -40);
  });

  group('MidiFakeBluetoothBackend', () {
    group('MidiFakeBluetoothBackend({backend})', () {
      test('belongs to its backend', () {
        expect(
          MidiFakeBluetoothBackend(backend: backend).backend,
          same(backend),
        );
        expect([bluetooth.peripherals, bluetooth.isScanning], [isEmpty, false]);
      });
    });

    group('scan({timeout}), stopScan()', () {
      test('reports known and new peripherals until stopped', () async {
        bluetooth.addPeripheral(keys);
        final found = <MidiBlePeripheralInfo>[];
        final done = bluetooth.scan().listen(found.add).asFuture<void>();
        await pumpEventQueue();
        expect(bluetooth.isScanning, isTrue);
        final pad = MidiBlePeripheralInfo(id: 'CC:DD', name: 'Pad');
        bluetooth.addPeripheral(pad);
        await bluetooth.stopScan();
        await done;
        expect(found, equals([keys, pad]));
        expect(bluetooth.isScanning, isFalse);
        expect(bluetooth.peripherals, equals([keys, pad]));
      });

      test('ends after the timeout', () async {
        final scan = bluetooth
            .scan(timeout: const Duration(seconds: 2))
            .toList();
        await pumpEventQueue();
        timers.advance(const Duration(seconds: 2));
        expect(await scan, isEmpty);
        expect(bluetooth.isScanning, isFalse);
      });

      test('ends when the listener cancels', () async {
        final subscription = bluetooth
            .scan(timeout: const Duration(seconds: 2))
            .listen((_) {});
        await pumpEventQueue();
        await subscription.cancel();
        expect([bluetooth.isScanning, timers.pending], [false, 0]);
      });
    });

    group('connect(peripheralId, {timeout})', () {
      test('adds an input and an output port', () async {
        bluetooth.addPeripheral(keys);
        final ports = await bluetooth.connect('AA:BB');
        const device = MidiDeviceId('fake:AA:BB');
        expect(
          ports,
          equals([
            MidiPortInfo(
              id: const MidiPortId('fake:AA:BB/input'),
              deviceId: device,
              name: 'Keys',
              direction: MidiDirection.input,
              transport: MidiTransport.bluetoothLe,
              capabilities: const MidiPortCapabilities(timestampsIn: true),
              serialNumber: 'AA:BB',
            ),
            MidiPortInfo(
              id: const MidiPortId('fake:AA:BB/output'),
              deviceId: device,
              name: 'Keys',
              direction: MidiDirection.output,
              transport: MidiTransport.bluetoothLe,
              capabilities: const MidiPortCapabilities(timestampsIn: true),
              serialNumber: 'AA:BB',
            ),
          ]),
        );
        expect(backend.ports, equals(ports));
        expect(
          bluetooth.peripherals.single,
          keys.copyWith(
            state: MidiBlePeripheralState.connected,
            portIds: [for (final port in ports) port.id],
          ),
        );
        expect(await bluetooth.connect('AA:BB'), same(ports));
      });

      test('names the ports after the id without a name', () async {
        bluetooth.addPeripheral(MidiBlePeripheralInfo(id: 'EE'));
        final ports = await bluetooth.connect('EE');
        expect(ports.first.name, 'EE');
      });

      test('throws for unknown peripherals', () async {
        await expectLater(
          bluetooth.connect('none'),
          throwsA(
            isA<MidiPortGone>().having(
              (e) => e.port,
              'port',
              const MidiPortId('fake:none'),
            ),
          ),
        );
      });
    });

    group('disconnect(peripheralId)', () {
      test('removes the ports of the peripheral', () async {
        bluetooth.addPeripheral(keys);
        final ports = await bluetooth.connect('AA:BB');
        backend.removePort(ports.first.id);
        await bluetooth.disconnect('AA:BB');
        await bluetooth.disconnect('AA:BB');
        await bluetooth.disconnect('unknown');
        expect(backend.ports, isEmpty);
        expect(
          bluetooth.peripherals.single,
          keys.copyWith(state: MidiBlePeripheralState.disconnected),
        );
      });
    });
  });
}
