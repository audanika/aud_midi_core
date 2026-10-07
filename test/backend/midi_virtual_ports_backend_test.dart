// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

/// Virtual ports that only live in a list.
final class _ListedPorts implements MidiVirtualPortsBackend {
  final ports = <MidiPortInfo>[];

  @override
  Future<MidiPortInfo> create(MidiVirtualPortSpec spec) async {
    final port = MidiPortInfo(
      id: MidiPortId.of(backend: 'list', nativeId: spec.name),
      name: spec.name,
      direction: spec.direction,
      isVirtual: true,
      isOwn: true,
    );
    ports.add(port);
    return port;
  }

  @override
  Future<void> remove(MidiPortId port) async =>
      ports.removeWhere((known) => known.id == port);
}

void main() {
  group('MidiVirtualPortsBackend', () {
    test('is implemented by the package', () {
      expect(FakeMidiBackend().virtualPorts, isA<MidiVirtualPortsBackend>());
    });

    test('creates own ports and removes them', () async {
      final listed = _ListedPorts();
      final MidiVirtualPortsBackend virtualPorts = listed;
      final port = await virtualPorts.create(
        MidiVirtualPortSpec(name: 'Synth', direction: MidiDirection.input),
      );
      expect([
        port.isOwn,
        port.isVirtual,
        port.isInput,
      ], equals([true, true, true]));
      expect(listed.ports, equals([port]));
      await virtualPorts.remove(port.id);
      expect(listed.ports, isEmpty);
    });
  });
}
