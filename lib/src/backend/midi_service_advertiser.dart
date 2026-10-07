// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'midi_service_registration.dart';

// #############################################################################
/// Advertises a network service through the operating system's DNS-SD
/// registrar, e.g. `NsdManager` on Android, `DnsServiceRegister` on
/// Windows or Avahi on Linux.
///
/// The network package uses it to announce `_apple-midi._udp` and
/// `_midi2._udp` sessions without an mDNS responder of its own.
abstract interface class MidiServiceAdvertiser {
  // ...........................................................................
  /// Registers the service [name] of [type], e.g. `_apple-midi._udp`, on
  /// [port] with the TXT record entries [txt].
  Future<MidiServiceRegistration> register({
    required String name,
    required String type,
    required int port,
    Map<String, String> txt = const {},
  });
}
