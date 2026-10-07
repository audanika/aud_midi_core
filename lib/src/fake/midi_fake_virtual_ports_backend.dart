// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../backend/midi_virtual_ports_backend.dart';
import '../error/midi_exception.dart';
import 'fake_midi_backend.dart';

// #############################################################################
/// The in-memory virtual ports of a [FakeMidiBackend].
///
/// A created port appears on the backend as an own virtual port with the
/// id `'<backend>:virtual-<n>'`; a MIDI 2.0 port exchanges UMP. The spec's
/// unique id and model go to [MidiPortInfo.native].
final class MidiFakeVirtualPortsBackend implements MidiVirtualPortsBackend {
  /// Creates the virtual ports of [backend].
  MidiFakeVirtualPortsBackend({required this.backend});

  // ...........................................................................
  @override
  Future<MidiPortInfo> create(MidiVirtualPortSpec spec) async {
    final port = MidiPortInfo(
      id: MidiPortId.of(backend: backend.name, nativeId: 'virtual-${_next++}'),
      name: spec.name,
      manufacturer: spec.manufacturer,
      direction: spec.direction,
      transport: MidiTransport.virtual,
      protocol: spec.protocol,
      isVirtual: true,
      isOwn: true,
      groups: [for (final group in spec.groups) MidiGroupInfo(group: group)],
      capabilities: MidiPortCapabilities(
        ump: spec.protocol == MidiProtocol.midi2,
      ),
      native: {'uniqueId': spec.uniqueId, 'model': spec.model},
    );
    _created.add(port.id);
    return backend.addPort(port);
  }

  /// Removes the own virtual [port]; throws a [MidiPortGone] for a port
  /// these virtual ports did not create.
  @override
  Future<void> remove(MidiPortId port) async {
    if (!_created.remove(port)) throw MidiPortGone(port);
    if (backend.port(port) != null) backend.removePort(port);
  }

  // ...........................................................................
  /// The backend the ports appear on.
  final FakeMidiBackend backend;

  /// The ids of the created ports that were not removed; cannot be
  /// modified.
  List<MidiPortId> get created => List.unmodifiable(_created);

  // ...........................................................................
  final _created = <MidiPortId>[];
  int _next = 0;
}
