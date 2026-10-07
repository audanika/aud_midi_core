// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// The runtime contracts of the aud_midi family: backend interfaces, the
/// package clock, the engine that hosts a backend, scheduling, the port
/// registry, diagnostics and a fake backend for tests.
library;

export 'src/backend/midi_backend.dart';
export 'src/backend/midi_backend_host.dart';
export 'src/backend/midi_bluetooth_backend.dart';
export 'src/backend/midi_composite_backend.dart';
export 'src/backend/midi_network_backend.dart';
export 'src/backend/midi_service_advertiser.dart';
export 'src/backend/midi_service_registration.dart';
export 'src/backend/midi_virtual_ports_backend.dart';
export 'src/ble/midi_ble_bluetooth_backend.dart';
export 'src/ble/midi_ble_connection.dart';
export 'src/ble/midi_ble_transport.dart';
export 'src/clock/midi_clock.dart';
export 'src/clock/midi_clock_mapper.dart';
export 'src/clock/midi_fake_clock.dart';
export 'src/clock/midi_fake_timers.dart';
export 'src/clock/midi_system_clock.dart';
export 'src/clock/midi_timer_factory.dart';
export 'src/engine/midi_diagnostics_bus.dart';
export 'src/engine/midi_diagnostics_snapshot.dart';
export 'src/engine/midi_engine.dart';
export 'src/engine/midi_engine_options.dart';
export 'src/engine/midi_input_options.dart';
export 'src/engine/midi_input_session.dart';
export 'src/engine/midi_note_tracker.dart';
export 'src/engine/midi_output_session.dart';
export 'src/engine/midi_panic.dart';
export 'src/engine/midi_port_registry.dart';
export 'src/engine/midi_software_scheduler.dart';
export 'src/error/midi_exception.dart';
export 'src/fake/fake_midi_backend.dart';
export 'src/fake/midi_fake_bluetooth_backend.dart';
export 'src/fake/midi_fake_network_backend.dart';
export 'src/fake/midi_fake_virtual_ports_backend.dart';
