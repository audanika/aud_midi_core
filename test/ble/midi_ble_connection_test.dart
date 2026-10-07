// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:typed_data';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:test/test.dart';

/// A connection that echoes every written packet as a notification.
final class _EchoConnection implements MidiBleConnection {
  final _notifications = StreamController<Uint8List>();
  final _done = Completer<void>();

  @override
  Future<void> write(Uint8List packet) async => _notifications.add(packet);

  @override
  Future<void> disconnect() async {
    await _notifications.close();
    _done.complete();
  }

  @override
  String get peripheralId => 'echo';

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  int get maxPacketLength => 20;

  @override
  Future<void> get done => _done.future;
}

void main() {
  group('MidiBleConnection', () {
    test('runs an implementation through the whole contract', () async {
      final MidiBleConnection connection = _EchoConnection();
      final received = connection.notifications.toList();
      await connection.write(Uint8List.fromList([0x80, 0x80, 0xF8]));
      await connection.disconnect();
      await connection.done;
      expect(
        await received,
        equals([
          [0x80, 0x80, 0xF8],
        ]),
      );
      expect(connection.peripheralId, 'echo');
      expect(connection.maxPacketLength, 20);
    });
  });
}
