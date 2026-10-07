// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A connection that is never used.
final class _IdleConnection implements MidiBleConnection {
  _IdleConnection(this.peripheralId);

  @override
  final String peripheralId;

  @override
  Future<void> write(Uint8List packet) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<Uint8List> get notifications => const Stream.empty();

  @override
  int get maxPacketLength => 20;

  @override
  Future<void> get done => Future.value();
}

/// A transport that finds one peripheral.
final class _OneTransport implements MidiBleTransport {
  final log = <String>[];

  @override
  Stream<MidiBlePeripheralInfo> scan({Duration? timeout}) {
    log.add('scan');
    return Stream.value(MidiBlePeripheralInfo(id: 'p1'));
  }

  @override
  Future<void> stopScan() async => log.add('stopScan');

  @override
  Future<MidiBleConnection> connect(
    String peripheralId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    log.add('connect $peripheralId');
    return _IdleConnection(peripheralId);
  }
}

void main() {
  group('MidiBleTransport', () {
    test('names the BLE-MIDI service and characteristic', () {
      expect(
        MidiBleTransport.serviceUuid,
        '03b80e5a-ede8-4b33-a751-6ce34ec4c700',
      );
      expect(
        MidiBleTransport.characteristicUuid,
        '7772e5db-3868-4112-a1a9-f2669d106bf3',
      );
    });

    test('runs an implementation through the whole contract', () async {
      final one = _OneTransport();
      final MidiBleTransport transport = one;
      final found = await transport.scan().toList();
      await transport.stopScan();
      final connection = await transport.connect(found.single.id);
      expect(connection.peripheralId, 'p1');
      expect(one.log, equals(['scan', 'stopScan', 'connect p1']));
    });
  });
}
