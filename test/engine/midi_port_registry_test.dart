// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  late MidiPortRegistry registry;

  // Returns a port of the fake backend.
  MidiPortInfo port(
    String nativeId, {
    MidiDirection direction = MidiDirection.input,
    String? name,
    MidiDeviceId? deviceId,
    String serialNumber = '',
    MidiPortState state = MidiPortState.connected,
    Map<String, Object?> native = const {},
  }) => MidiPortInfo(
    id: MidiPortId.of(backend: 'fake', nativeId: nativeId),
    deviceId: deviceId,
    name: name ?? nativeId,
    manufacturer: 'Audanika',
    direction: direction,
    state: state,
    serialNumber: serialNumber,
    native: native,
  );

  setUp(() => registry = MidiPortRegistry());

  group('MidiPortRegistry', () {
    group('reset(ports)', () {
      test('replaces the ports without events', () async {
        final events = registry.events.toList();
        registry
          ..reset([port('a')])
          ..reset([port('b'), port('c', direction: MidiDirection.output)]);
        await registry.close();
        expect(await events, isEmpty);
        expect(
          registry.ports,
          equals([port('b'), port('c', direction: MidiDirection.output)]),
        );
      });
    });

    group('apply(events)', () {
      test('adds, changes and removes ports', () async {
        final published = registry.events.toList();
        final renamed = port('a', name: 'renamed');
        final applied = [
          ...registry.apply([MidiPortAdded(port: port('a'))]),
          ...registry.apply([
            MidiPortChanged(port: renamed, previous: port('x')),
            MidiPortRemoved(port: port('a')),
          ]),
        ];
        await registry.close();
        expect(
          applied,
          equals([
            MidiPortAdded(port: port('a')),
            MidiPortChanged(port: renamed, previous: port('a')),
            MidiPortRemoved(port: renamed),
          ]),
        );
        expect(await published, equals(applied));
        expect(registry.ports, isEmpty);
      });

      test('normalises events against the known ports', () {
        registry.reset([port('a')]);
        final renamed = port('a', name: 'renamed');
        expect(
          registry.apply([
            MidiPortAdded(port: port('a')),
            MidiPortRemoved(port: port('unknown')),
            MidiPortAdded(port: renamed),
            MidiPortChanged(port: renamed, previous: port('a')),
            MidiPortChanged(port: port('new'), previous: port('new')),
          ]),
          equals([
            MidiPortChanged(port: renamed, previous: port('a')),
            MidiPortAdded(port: port('new')),
          ]),
        );
      });

      test('takes over native extras silently', () {
        registry.reset([port('a')]);
        final applied = registry.apply([
          MidiPortChanged(
            port: port('a', native: const {'handle': 7}),
            previous: port('a'),
          ),
        ]);
        expect(applied, isEmpty);
        expect(registry.port(port('a').id)!.native, equals({'handle': 7}));
      });

      test('keeps applying after close without publishing', () async {
        await registry.close();
        expect(registry.isClosed, isTrue);
        expect(
          registry.apply([MidiPortAdded(port: port('a'))]),
          equals([MidiPortAdded(port: port('a'))]),
        );
        expect(registry.ports, equals([port('a')]));
      });
    });

    group('port(id)', () {
      test('returns a known port or null', () {
        registry.reset([port('a')]);
        expect(registry.port(port('a').id), port('a'));
        expect(registry.port(const MidiPortId('fake:b')), isNull);
      });
    });

    group('ports, inputs, outputs', () {
      test('list the ports by direction, unmodifiable', () {
        final output = port('o', direction: MidiDirection.output);
        registry.reset([port('i'), output]);
        expect(registry.inputs, equals([port('i')]));
        expect(registry.outputs, equals([output]));
        expect(() => registry.ports.clear(), throwsUnsupportedError);
        expect(() => registry.inputs.clear(), throwsUnsupportedError);
        expect(() => registry.outputs.clear(), throwsUnsupportedError);
      });
    });

    group('replugCandidates(port)', () {
      test('returns the other ports with the same fingerprint', () {
        final gone = port('old', name: 'Keys', serialNumber: '42');
        final back = port('new', name: 'Keys', serialNumber: '42');
        final twinA = port('twinA', name: 'Pad');
        final twinB = port('twinB', name: 'Pad');
        registry.reset([back, twinA, twinB, port('other', name: 'Other')]);
        expect(registry.replugCandidates(gone), equals([back]));
        expect(registry.replugCandidates(back), isEmpty);
        expect(registry.replugCandidates(twinA), equals([twinB]));
        expect(
          registry.replugCandidates(port('lost', name: 'Pad')),
          equals([twinA, twinB]),
        );
      });
    });

    group('devices', () {
      test('groups the ports of each device', () {
        const keys = MidiDeviceId('fake:keys');
        const pad = MidiDeviceId('fake:pad');
        registry.reset([
          port(
            'k1',
            name: 'Keys MIDI 1',
            deviceId: keys,
            serialNumber: '42',
            native: const {
              MidiPortRegistry.deviceNameKey: 'Keys',
              MidiPortRegistry.productKey: 'Keys 61',
              MidiPortRegistry.driverKey: 'USB Audio',
            },
          ),
          port('loose'),
          port(
            'p1',
            deviceId: pad,
            state: MidiPortState.offline,
            native: const {MidiPortRegistry.deviceNameKey: 7},
          ),
          port('k2', deviceId: keys, direction: MidiDirection.output),
          port('p2', deviceId: pad, state: MidiPortState.offline),
        ]);
        expect(
          registry.devices,
          equals([
            MidiDeviceInfo(
              id: keys,
              name: 'Keys',
              manufacturer: 'Audanika',
              product: 'Keys 61',
              serialNumber: '42',
              driver: 'USB Audio',
              ports: [port('k1').id, port('k2').id],
            ),
            MidiDeviceInfo(
              id: pad,
              name: 'p1',
              manufacturer: 'Audanika',
              driver: 'fake',
              isOffline: true,
              ports: [port('p1').id, port('p2').id],
            ),
          ]),
        );
      });
    });

    group('events', () {
      test('is a broadcast stream', () {
        expect(registry.events.isBroadcast, isTrue);
      });
    });
  });
}
