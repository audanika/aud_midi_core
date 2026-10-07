// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// A session that replays fixed events.
final class _ReplaySession implements MidiInputSession {
  _ReplaySession(this.recorded);

  final List<MidiEvent> recorded;
  final _done = Completer<void>();

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  MidiPortInfo get port => MidiPortInfo(
    id: const MidiPortId('replay:in'),
    name: 'replay',
    direction: MidiDirection.input,
  );

  @override
  MidiInputOptions get options => const MidiInputOptions();

  @override
  Stream<MidiEvent> get events => Stream.fromIterable(recorded);

  @override
  Stream<MidiPacket> get packets => const Stream.empty();

  @override
  bool get isClosed => _done.isCompleted;

  @override
  Future<void> get done => _done.future;
}

void main() {
  group('MidiInputSession', () {
    test('runs an implementation through the whole contract', () async {
      const event = MidiEvent(message: MidiStart(), time: MidiTime(1));
      final MidiInputSession session = _ReplaySession([event]);
      expect(await session.events.toList(), equals([event]));
      expect(await session.packets.toList(), isEmpty);
      expect(session.port.isInput, isTrue);
      expect(session.options, const MidiInputOptions());
      expect(session.isClosed, isFalse);
      await session.close();
      await session.done;
      expect(session.isClosed, isTrue);
    });

    test('is what MidiEngine.openInput returns', () async {
      final backend = FakeMidiBackend();
      final input = backend.addPort(
        backend.portInfo('in', direction: MidiDirection.input),
      );
      final engine = MidiEngine(backend: backend);
      await engine.open();
      final session = await engine.openInput(input.id);
      expect(session, isA<MidiInputSession>());
      expect(session.port, input);
      await engine.close();
      expect(session.isClosed, isTrue);
    });
  });
}
