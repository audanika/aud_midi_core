// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// A service registered by a `MidiServiceAdvertiser`.
abstract interface class MidiServiceRegistration {
  // ...........................................................................
  /// Withdraws the registration.
  Future<void> unregister();

  // ...........................................................................
  /// The name under which the service is registered; the registrar may
  /// have renamed it to resolve a conflict.
  String get name;
}
