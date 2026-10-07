// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_core/aud_midi_core.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  const mac = MidiNetworkHostInfo(
    name: 'Mac',
    address: '10.0.0.2',
    port: 5004,
    source: MidiNetworkHostSource.bonjour,
  );
  const pc = MidiNetworkHostInfo(name: 'PC', address: '10.0.0.3', port: 5006);
  late FakeMidiBackend backend;
  late MidiFakeNetworkBackend network;
  late List<MidiNetworkSessionInfo> changes;

  setUp(() {
    backend = FakeMidiBackend();
    network = backend.network!;
    changes = [];
    network.sessionChanges.listen(changes.add);
  });

  group('MidiFakeNetworkBackend', () {
    group('MidiFakeNetworkBackend({backend})', () {
      test('starts with a disabled AppleMIDI session', () {
        expect(MidiFakeNetworkBackend(backend: backend).backend, same(backend));
        expect(
          network.session,
          MidiNetworkSessionInfo(
            localName: '',
            enabled: false,
            port: MidiFakeNetworkBackend.defaultPort,
            protocol: MidiNetworkProtocol.appleMidi,
            connectionPolicy: MidiNetworkConnectionPolicy.anyone,
          ),
        );
        expect(network.hosts, isEmpty);
      });
    });

    group('enable({name, port, policy}), disable()', () {
      test('switch the session and report it', () async {
        final enabled = await network.enable(name: 'Studio');
        expect(
          [enabled.enabled, enabled.localName, enabled.port],
          [true, 'Studio', 5004],
        );
        final custom = await network.enable(
          name: 'Stage',
          port: 6000,
          policy: MidiNetworkConnectionPolicy.specificPeers,
        );
        expect(custom.port, 6000);
        expect(
          custom.connectionPolicy,
          MidiNetworkConnectionPolicy.specificPeers,
        );
        await network.connect(mac);
        await network.disable();
        await pumpEventQueue();
        expect(network.session.enabled, isFalse);
        expect(network.session.connections, isEmpty);
        expect(backend.ports, isEmpty);
        expect(changes, hasLength(4));
        expect(changes.last, network.session);
      });
    });

    group('connect(host), disconnect(host)', () {
      test('add and remove the ports of a connection', () async {
        await network.enable(name: 'Studio');
        final connection = await network.connect(mac);
        expect(
          connection,
          MidiNetworkConnectionInfo(
            host: mac,
            state: MidiNetworkConnectionState.connected,
            portIds: const [
              MidiPortId('fake:10.0.0.2:5004/input'),
              MidiPortId('fake:10.0.0.2:5004/output'),
            ],
          ),
        );
        expect(
          backend.ports.first,
          MidiPortInfo(
            id: const MidiPortId('fake:10.0.0.2:5004/input'),
            name: 'Mac',
            direction: MidiDirection.input,
            transport: MidiTransport.network,
          ),
        );
        expect(await network.connect(mac), same(connection));
        await network.connect(pc);
        await network.disconnect(mac);
        await network.disconnect(mac);
        expect(network.session.connections.single.host, pc);
        expect(backend.ports, hasLength(2));
      });

      test('connect needs an enabled session', () async {
        await expectLater(
          network.connect(mac),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'The session is not enabled',
            ),
          ),
        );
      });

      test('tolerate ports the backend lost already', () async {
        await network.enable(name: 'Studio');
        final connection = await network.connect(mac);
        backend.removePort(connection.portIds.first);
        await network.disconnect(mac);
        expect(backend.ports, isEmpty);
      });
    });

    group('browse()', () {
      test('reports the hosts now and after every change', () async {
        network.addHost(mac);
        final lists = <List<MidiNetworkHostInfo>>[];
        final subscription = network.browse().listen(lists.add);
        await pumpEventQueue();
        network
          ..addHost(pc)
          ..removeHost(mac)
          ..removeHost(mac);
        await pumpEventQueue();
        await subscription.cancel();
        network.addHost(mac);
        await pumpEventQueue();
        expect(
          lists,
          equals([
            [mac],
            [mac, pc],
            [pc],
          ]),
        );
        expect(network.hosts, equals([pc, mac]));
        expect(() => network.hosts.clear(), throwsUnsupportedError);
      });
    });
  });
}
