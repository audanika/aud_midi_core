// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// Creates ports that other applications see.
///
/// A virtual port with direction [MidiDirection.output] is a source the
/// app sends from; one with [MidiDirection.input] is a destination other
/// apps send to, delivered to the app like any input.
abstract interface class MidiVirtualPortsBackend {
  // ...........................................................................
  /// Creates the virtual port described by [spec] and returns it with
  /// `isOwn` set.
  Future<MidiPortInfo> create(MidiVirtualPortSpec spec);

  // ...........................................................................
  /// Removes the own virtual [port].
  Future<void> remove(MidiPortId port);
}
