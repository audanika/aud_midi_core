// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  late FakeMidiBackend backend;
  late MidiFakeVirtualPortsBackend virtualPorts;

  setUp(() {
    backend = FakeMidiBackend();
    virtualPorts = backend.virtualPorts!;
  });

  group('MidiFakeVirtualPortsBackend', () {
    group('MidiFakeVirtualPortsBackend({backend})', () {
      test('belongs to its backend', () {
        expect(
          MidiFakeVirtualPortsBackend(backend: backend).backend,
          same(backend),
        );
        expect(virtualPorts.created, isEmpty);
      });
    });

    group('create(spec)', () {
      test('adds an own virtual port to the backend', () async {
        final midi1 = await virtualPorts.create(
          MidiVirtualPortSpec(
            name: 'Synth',
            direction: MidiDirection.input,
            uniqueId: 42,
            groups: [1, 2],
            manufacturer: 'Audanika',
            model: 'S1',
          ),
        );
        expect(
          midi1,
          MidiPortInfo(
            id: const MidiPortId('fake:virtual-0'),
            name: 'Synth',
            manufacturer: 'Audanika',
            direction: MidiDirection.input,
            transport: MidiTransport.virtual,
            isVirtual: true,
            isOwn: true,
            groups: const [MidiGroupInfo(group: 1), MidiGroupInfo(group: 2)],
          ),
        );
        expect(midi1.native, equals({'uniqueId': 42, 'model': 'S1'}));
        final midi2 = await virtualPorts.create(
          MidiVirtualPortSpec(
            name: 'UMP',
            direction: MidiDirection.output,
            protocol: MidiProtocol.midi2,
          ),
        );
        expect(midi2.id, const MidiPortId('fake:virtual-1'));
        expect(midi2.capabilities.ump, isTrue);
        expect(backend.ports, equals([midi1, midi2]));
        expect(virtualPorts.created, equals([midi1.id, midi2.id]));
        expect(() => virtualPorts.created.clear(), throwsUnsupportedError);
      });
    });

    group('remove(port)', () {
      test('removes an own port from the backend', () async {
        final port = await virtualPorts.create(
          MidiVirtualPortSpec(name: 'x', direction: MidiDirection.input),
        );
        await virtualPorts.remove(port.id);
        expect([backend.ports, virtualPorts.created], [isEmpty, isEmpty]);
      });

      test('tolerates a port the backend lost already', () async {
        final port = await virtualPorts.create(
          MidiVirtualPortSpec(name: 'x', direction: MidiDirection.input),
        );
        backend.removePort(port.id);
        await virtualPorts.remove(port.id);
        expect(virtualPorts.created, isEmpty);
      });

      test('throws for ports it did not create', () async {
        final other = backend.addPort(
          backend.portInfo('other', direction: MidiDirection.input),
        );
        await expectLater(
          virtualPorts.remove(other.id),
          throwsA(isA<MidiPortGone>()),
        );
      });
    });
  });
}
