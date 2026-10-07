// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A session that logs what it is asked to do.
final class _LoggingSession implements MidiOutputSession {
  final log = <String>[];
  bool _isClosed = false;

  @override
  Future<void> send(MidiMessage message, {MidiTime? at, int? group}) async =>
      log.add('send ${message.runtimeType} ${at?.microseconds} $group');

  @override
  Future<void> sendAll(
    Iterable<MidiMessage> messages, {
    MidiTime? at,
    int? group,
  }) async => log.add('sendAll ${messages.length}');

  @override
  Future<void> sendPacket(MidiPacket packet) async =>
      log.add('sendPacket ${packet.time.microseconds}');

  @override
  Future<int> cancelPending() async {
    log.add('cancelPending');
    return 0;
  }

  @override
  Future<void> panic({MidiPanic panic = const MidiPanic()}) async =>
      log.add('panic ${panic.channels.length}');

  @override
  Future<void> close() async => _isClosed = true;

  @override
  MidiPortInfo get port => MidiPortInfo(
    id: const MidiPortId('log:out'),
    name: 'log',
    direction: MidiDirection.output,
  );

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> get done => Future.value();
}

void main() {
  group('MidiOutputSession', () {
    test('runs an implementation through the whole contract', () async {
      final logging = _LoggingSession();
      final MidiOutputSession session = logging;
      await session.send(const MidiStart(), at: const MidiTime(5), group: 2);
      await session.sendAll(const [MidiStart(), MidiStop()]);
      await session.sendPacket(
        MidiBytesPacket(bytes: MidiBytes([0xF8]), time: const MidiTime(9)),
      );
      expect(await session.cancelPending(), 0);
      await session.panic();
      await session.close();
      await session.done;
      expect(
        logging.log,
        equals([
          'send MidiStart 5 2',
          'sendAll 2',
          'sendPacket 9',
          'cancelPending',
          'panic 16',
        ]),
      );
      expect([session.isClosed, session.port.isOutput], equals([true, true]));
    });

    test('is what MidiEngine.openOutput returns', () async {
      final backend = FakeMidiBackend();
      final output = backend.addPort(
        backend.portInfo('out', direction: MidiDirection.output),
      );
      final engine = MidiEngine(backend: backend);
      await engine.open();
      final session = await engine.openOutput(output.id);
      expect(session, isA<MidiOutputSession>());
      expect(session.port, output);
      await engine.close();
      expect(session.isClosed, isTrue);
    });
  });
}
