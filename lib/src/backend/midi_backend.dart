// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_backend_host.dart';
import 'midi_bluetooth_backend.dart';
import 'midi_network_backend.dart';
import 'midi_virtual_ports_backend.dart';

// #############################################################################
/// The contract every operating system backend implements.
///
/// A backend runs in the isolate of the engine that hosts it — the MIDI
/// isolate in apps. It owns all native resources and reports through the
/// [MidiBackendHost] given to [start]. It works on raw packets only:
/// parsing, translation and scheduling in software belong to the engine.
///
/// Ports with [MidiPortCapabilities.ump] exchange UMP words
/// ([MidiUmpPacket]); all other ports exchange MIDI 1.0 bytes
/// ([MidiBytesPacket]).
///
/// Port ids start with [name] and a colon; the rest is the backend's own
/// business, e.g. a direction prefix where native ids of inputs and
/// outputs may collide. Nobody else interprets it.
abstract interface class MidiBackend {
  // ...........................................................................
  /// Starts the backend: creates the native client, enumerates the ports
  /// and begins to watch for hotplug.
  ///
  /// Throws a `MidiException` when the platform lacks MIDI support or a
  /// permission, and a [StateError] when the backend runs already.
  Future<void> start(MidiBackendHost host);

  // ...........................................................................
  /// Stops the backend and releases all native resources.
  ///
  /// It first stops the native sources, then waits until no native
  /// callback is in flight, and only then frees callbacks and buffers.
  Future<void> stop();

  // ...........................................................................
  /// Opens [port]: an input starts to deliver packets, an output gets
  /// ready to send.
  ///
  /// Throws a `MidiPortGone` for an unknown port.
  Future<void> openPort(MidiPortId port);

  /// Closes [port]; an input stops delivering packets.
  ///
  /// Closing a port that is unknown or not open does nothing. When an open
  /// port disappears, the backend closes it on its own and reports the
  /// removal; a port that comes back has to be opened again.
  Future<void> closePort(MidiPortId port);

  // ...........................................................................
  /// Sends [packet] to the output [port].
  ///
  /// The packet's time is the due time on the package clock; a time in the
  /// past means now. Ports without [MidiPortCapabilities.scheduledSend]
  /// only receive due packets, the engine schedules them in software. The
  /// future completes when the port accepted the packet. The calls for one
  /// port arrive in the order the packets have to leave; the backend keeps
  /// that order.
  ///
  /// Throws an [ArgumentError] for an input port and a `MidiUnsupported`
  /// for a packet of the other raw form.
  Future<void> send(MidiPortId port, MidiPacket packet);

  /// Discards the packets the output [port] has not sent yet.
  ///
  /// The engine calls it only for ports with
  /// [MidiPortCapabilities.cancelPending]. Throws an [ArgumentError] for an
  /// input port.
  Future<void> cancelPending(MidiPortId port);

  // ...........................................................................
  /// The short name of the backend, also the prefix of its port ids, e.g.
  /// `coremidi`.
  String get name;

  /// What the backend supports on this device.
  MidiCapabilities get capabilities;

  /// The ports known right now.
  List<MidiPortInfo> get ports;

  /// The virtual port support, or null when the platform has none.
  MidiVirtualPortsBackend? get virtualPorts;

  /// The Bluetooth LE MIDI support, or null when the platform has none.
  MidiBluetoothBackend? get bluetooth;

  /// The network session support, or null when the platform has none.
  MidiNetworkBackend? get network;
}
