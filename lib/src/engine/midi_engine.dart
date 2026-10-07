// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../backend/midi_backend.dart';
import '../backend/midi_backend_host.dart';
import '../backend/midi_bluetooth_backend.dart';
import '../backend/midi_network_backend.dart';
import '../backend/midi_virtual_ports_backend.dart';
import '../clock/midi_clock.dart';
import '../clock/midi_system_clock.dart';
import '../clock/midi_timer_factory.dart';
import '../error/midi_exception.dart';
import 'midi_diagnostics_bus.dart';
import 'midi_diagnostics_snapshot.dart';
import 'midi_engine_options.dart';
import 'midi_input_options.dart';
import 'midi_input_pipeline.dart';
import 'midi_input_session.dart';
import 'midi_output_pipeline.dart';
import 'midi_output_session.dart';
import 'midi_panic.dart';
import 'midi_port_registry.dart';
import 'midi_software_scheduler.dart';

// #############################################################################
/// Hosts one backend in the current isolate and turns its raw packets into
/// typed events and typed messages into its raw packets.
///
/// The engine runs entirely in the isolate that creates it and starts no
/// isolate of its own; apps host it in a dedicated MIDI isolate so that a
/// busy app isolate never delays it. It owns the port registry, one input
/// pipeline per open input, one output pipeline per open output, the
/// software scheduler and the diagnostics bus.
///
/// - Inputs: [openInput] returns a session with typed events and raw
///   packets; byte ports are parsed, UMP ports decoded, JR timestamps
///   consumed, channel voice messages optionally translated, see
///   [MidiInputSession].
/// - Outputs: [openOutput] returns a session that translates, encodes and
///   schedules, see [MidiOutputSession].
/// - Losses become diagnostics on [diagnostics]. A backend diagnostic of
///   kind [MidiDiagnosticKind.queueOverflow] or
///   [MidiDiagnosticKind.networkLoss] for an open input marks a gap in its
///   stream: the engine drops the partial messages of the port.
/// - A removed port closes its sessions: input streams complete after the
///   values they queued, output sessions throw [MidiPortGone]. The backend
///   closed the native port already; when the port comes back, the next
///   [openInput] or [openOutput] opens it again.
///
/// [close] shuts down in a fixed order: it rejects new calls and ignores
/// the backend's reports, closes all sessions, closes the inputs in the
/// backend, discards the scheduled packets in the software scheduler and
/// the operating system, waits for the sends in flight, closes the
/// outputs, stops the backend and completes [portEvents] and
/// [diagnostics]. No event is delivered after [close] completed.
final class MidiEngine {
  /// Creates an engine for [backend].
  ///
  /// - [clock] the package clock; tests pass a `MidiFakeClock`.
  /// - [options] the settings of the engine.
  /// - [timerFactory] creates the timers of the software scheduler; tests
  ///   pass `MidiFakeTimers.create`.
  MidiEngine({
    required this.backend,
    this.clock = const MidiSystemClock(),
    this.options = const MidiEngineOptions(),
    MidiTimerFactory timerFactory = Timer.new,
  }) {
    _host = _MidiEngineHost(this);
    _scheduler = MidiSoftwareScheduler(
      clock: clock,
      dispatch: _dispatchScheduled,
      timerFactory: timerFactory,
      lateThreshold: options.lateThreshold,
      onDiagnostic: _report,
    );
  }

  // ...........................................................................
  /// Starts the backend and takes over its ports.
  ///
  /// Throws a [StateError] when the engine was opened before; a failing
  /// backend start leaves the engine ready for another try.
  Future<void> open() async {
    if (_state != _EngineState.created) {
      throw StateError('The engine is opened or closed already');
    }
    _state = _EngineState.opening;
    final opening = _start();
    _opening = opening;
    await opening;
  }

  /// Shuts the engine down in the order described at [MidiEngine]; calling
  /// it again returns the same future.
  ///
  /// Throws what the backend's stop threw, after the shutdown completed.
  Future<void> close() => _closing ??= _shutDown();

  // ...........................................................................
  /// Opens a session on the input port [id] with [options], or with
  /// [MidiEngineOptions.input].
  ///
  /// The first session of a port opens the native port. Throws a
  /// [MidiPortGone] for an unknown port and an [ArgumentError] for an
  /// output port.
  Future<MidiInputSession> openInput(
    MidiPortId id, {
    MidiInputOptions? options,
  }) async {
    _requirePort(id, MidiDirection.input);
    return _serialized(id, () async {
      final pipeline = _inputs[id] ?? await _openInputPipeline(id);
      return pipeline.open(options ?? this.options.input);
    });
  }

  /// Opens a session on the output port [id].
  ///
  /// The first session of a port opens the native port. Throws a
  /// [MidiPortGone] for an unknown port and an [ArgumentError] for an
  /// input port.
  Future<MidiOutputSession> openOutput(MidiPortId id) async {
    _requirePort(id, MidiDirection.output);
    return _serialized(id, () async {
      final pipeline = _outputs[id] ?? await _openOutputPipeline(id);
      return pipeline.open();
    });
  }

  // ...........................................................................
  /// Sends [message] to the open output [id], like
  /// [MidiOutputSession.send].
  ///
  /// Throws a [MidiPortGone] for an unknown port and a [StateError] when no
  /// session has the output open.
  Future<void> send(
    MidiPortId id,
    MidiMessage message, {
    MidiTime? at,
    int? group,
  }) async {
    await _openOutput(id).sendMessages([message], at: at, group: group);
  }

  /// Sends [messages] in one packet to the open output [id], like
  /// [MidiOutputSession.sendAll].
  Future<void> sendAll(
    MidiPortId id,
    Iterable<MidiMessage> messages, {
    MidiTime? at,
    int? group,
  }) async {
    await _openOutput(id).sendMessages(messages, at: at, group: group);
  }

  /// Sends the raw [packet] to the open output [id], like
  /// [MidiOutputSession.sendPacket].
  Future<void> sendPacket(MidiPortId id, MidiPacket packet) async {
    await _openOutput(id).sendPacket(packet);
  }

  /// Discards the pending messages of the open output [id] and returns the
  /// number of those that still leave, like
  /// [MidiOutputSession.cancelPending].
  Future<int> cancelPending(MidiPortId id) async =>
      _openOutput(id).cancelPending();

  /// Silences all open outputs as [panic] describes, like
  /// [MidiOutputSession.panic].
  Future<void> panic({MidiPanic panic = const MidiPanic()}) async {
    _checkOpen();
    await Future.wait([
      for (final output in [..._outputs.values]) output.panic(panic),
    ]);
  }

  // ...........................................................................
  /// Creates the virtual port described by [spec] and returns it.
  ///
  /// Throws a [MidiUnsupported] when the backend has no virtual ports.
  Future<MidiPortInfo> createVirtualPort(MidiVirtualPortSpec spec) async {
    final port = await _virtualPortsBackend().create(spec);
    _onPortsChanged([MidiPortAdded(port: port)]);
    return port;
  }

  /// Removes the own virtual port [id].
  ///
  /// Throws a [MidiUnsupported] when the backend has no virtual ports.
  Future<void> removeVirtualPort(MidiPortId id) async {
    await _virtualPortsBackend().remove(id);
    final port = _registry.port(id);
    if (port != null) _onPortsChanged([MidiPortRemoved(port: port)]);
  }

  // ...........................................................................
  /// Returns the port with [id], or null when it is unknown.
  MidiPortInfo? port(MidiPortId id) => _registry.port(id);

  /// Returns the other ports with the fingerprint of [port], see
  /// [MidiPortRegistry.replugCandidates].
  List<MidiPortInfo> replugCandidates(MidiPortInfo port) =>
      _registry.replugCandidates(port);

  /// Returns the current diagnostic counters.
  MidiDiagnosticsSnapshot diagnosticsSnapshot() => _bus.snapshot();

  // ...........................................................................
  /// The hosted backend.
  final MidiBackend backend;

  /// The package clock.
  final MidiClock clock;

  /// The settings of the engine.
  final MidiEngineOptions options;

  /// Whether [open] completed and [close] was not called yet.
  bool get isOpen => _state == _EngineState.open;

  /// Whether [close] completed.
  bool get isClosed => _state == _EngineState.closed;

  /// What the backend supports.
  MidiCapabilities get capabilities => backend.capabilities;

  /// The known ports.
  List<MidiPortInfo> get ports => _registry.ports;

  /// The known input ports.
  List<MidiPortInfo> get inputs => _registry.inputs;

  /// The known output ports.
  List<MidiPortInfo> get outputs => _registry.outputs;

  /// The devices of the known ports, see [MidiPortRegistry.devices].
  List<MidiDeviceInfo> get devices => _registry.devices;

  /// The ports that appear, disappear or change after [open].
  Stream<MidiPortEvent> get portEvents => _registry.events;

  /// The losses and faults of the backend and the engine.
  Stream<MidiDiagnostic> get diagnostics => _bus.diagnostics;

  /// The virtual port support of the backend, or null.
  MidiVirtualPortsBackend? get virtualPorts => backend.virtualPorts;

  /// The Bluetooth LE MIDI support of the backend, or null.
  MidiBluetoothBackend? get bluetooth => backend.bluetooth;

  /// The network session support of the backend, or null.
  MidiNetworkBackend? get network => backend.network;

  // ...........................................................................
  late final MidiBackendHost _host;
  late final MidiSoftwareScheduler _scheduler;
  final _registry = MidiPortRegistry();
  final _bus = MidiDiagnosticsBus();
  final _inputs = <MidiPortId, MidiInputPipeline>{};
  final _outputs = <MidiPortId, MidiOutputPipeline>{};
  final _portOperations = <MidiPortId, Future<void>>{};
  final _inFlight = <Future<void>>{};
  _EngineState _state = _EngineState.created;
  Future<void>? _opening;
  Future<void>? _closing;

  // ...........................................................................
  /// Starts the backend and fills the registry.
  Future<void> _start() async {
    try {
      await backend.start(_host);
    } on Object {
      _state = _EngineState.created;
      rethrow;
    }
    _registry.reset(backend.ports);
    _state = _EngineState.open;
  }

  /// Runs the shutdown.
  Future<void> _shutDown() async {
    await _opening?.then((_) {}, onError: (Object _) {});
    final wasOpen = isOpen;
    _state = _EngineState.closing;
    await Future.wait([..._portOperations.values]);
    final inputs = [..._inputs.values];
    final outputs = [..._outputs.values];
    _inputs.clear();
    _outputs.clear();
    for (final pipeline in inputs) {
      pipeline.close();
    }
    for (final pipeline in outputs) {
      pipeline.close();
    }
    Object? stopError;
    StackTrace? stopStack;
    if (wasOpen) {
      for (final pipeline in inputs) {
        await _closePort(pipeline.port.id);
      }
      await _cancelScheduled(outputs);
      await Future.wait([
        for (final send in [..._inFlight])
          send.then((_) {}, onError: (Object _) {}),
      ]);
      for (final pipeline in outputs) {
        await _closePort(pipeline.port.id);
      }
      try {
        await backend.stop();
      } on Object catch (error, stack) {
        stopError = error;
        stopStack = stack;
      }
    }
    _state = _EngineState.closed;
    await _registry.close();
    await _bus.close();
    if (stopError != null) Error.throwWithStackTrace(stopError, stopStack!);
  }

  /// Discards the scheduled packets in the software scheduler and in the
  /// backend for [outputs].
  Future<void> _cancelScheduled(List<MidiOutputPipeline> outputs) async {
    _scheduler.dispose();
    for (final pipeline in outputs) {
      if (!pipeline.port.capabilities.cancelPending) continue;
      try {
        await backend.cancelPending(pipeline.port.id);
      } on Object catch (error) {
        _nativeError(pipeline.port.id, 'Discarding pending packets', error);
      }
    }
  }

  // ...........................................................................
  /// Opens the native input [id] and creates its pipeline.
  Future<MidiInputPipeline> _openInputPipeline(MidiPortId id) async {
    final port = await _openNativePort(id);
    return _inputs[id] = MidiInputPipeline(
      port: port,
      clock: clock,
      onDiagnostic: _report,
      onEmpty: () => _release(id),
    );
  }

  /// Opens the native output [id] and creates its pipeline.
  Future<MidiOutputPipeline> _openOutputPipeline(MidiPortId id) async {
    final port = await _openNativePort(id);
    return _outputs[id] = MidiOutputPipeline(
      port: port,
      clock: clock,
      scheduler: _scheduler,
      send: _send,
      cancelBackend: backend.cancelPending,
      onDiagnostic: _report,
      onEmpty: () => _release(id),
      flushDataEntryMsb: options.flushDataEntryMsb,
      lookahead: options.lookahead,
    );
  }

  /// Opens the native port [id] and returns its current description.
  Future<MidiPortInfo> _openNativePort(MidiPortId id) async {
    _checkOpen();
    await backend.openPort(id);
    final port = _registry.port(id);
    if (port != null) return port;
    await _closePort(id);
    throw MidiPortGone(id);
  }

  /// Closes the native port [id] once its last session closed.
  Future<void> _release(MidiPortId id) => _serialized(id, () async {
    if (!isOpen) return;
    if (_inputs[id]?.isEmpty ?? false) {
      _inputs.remove(id);
      await _closePort(id);
    } else if (_outputs[id]?.isEmpty ?? false) {
      _outputs.remove(id);
      await _closePort(id);
    }
  });

  /// Closes the native port [id]; a failure becomes a diagnostic.
  Future<void> _closePort(MidiPortId id) async {
    try {
      await backend.closePort(id);
    } on Object catch (error) {
      _nativeError(id, 'Closing the port', error);
    }
  }

  /// Runs [operation] after the earlier operations on the port [id].
  Future<T> _serialized<T>(MidiPortId id, Future<T> Function() operation) {
    final previous = _portOperations[id] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    final settled = result.then<void>((_) {}, onError: (Object _) {});
    _portOperations[id] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_portOperations[id], settled)) {
          _portOperations.remove(id);
        }
      }),
    );
    return result;
  }

  // ...........................................................................
  /// Hands [packet] to the backend and keeps the send in flight until it
  /// completes.
  Future<void> _send(MidiPortId port, MidiPacket packet) {
    final send = Future<void>.sync(() => backend.send(port, packet));
    _inFlight.add(send);
    return send.whenComplete(() => _inFlight.remove(send));
  }

  /// Sends a packet the software scheduler found due; a failure becomes a
  /// diagnostic.
  void _dispatchScheduled(MidiPortId port, MidiPacket packet) {
    _outputs[port]?.handedOver(packet);
    unawaited(
      _send(port, packet).then(
        (_) {},
        onError: (Object error) =>
            _nativeError(port, 'Sending a scheduled packet', error),
      ),
    );
  }

  // ...........................................................................
  /// Applies the port [events] of the backend.
  void _onPortsChanged(List<MidiPortEvent> events) {
    if (_state != _EngineState.opening && !isOpen) return;
    for (final event in _registry.apply(events)) {
      switch (event) {
        case MidiPortRemoved(:final port):
          _portGone(port.id);
        case MidiPortChanged(:final port):
          _inputs[port.id]?.update(port);
          _outputs[port.id]?.update(port);
        case MidiPortAdded():
          break;
      }
    }
  }

  /// Closes the sessions of the removed port [id]; the backend closed the
  /// native port already, a port that comes back has to be opened again.
  void _portGone(MidiPortId id) {
    _inputs.remove(id)?.end();
    _outputs.remove(id)?.end();
  }

  /// Feeds [packet] received on [port] to its pipeline.
  void _onReceived(MidiPortId port, MidiPacket packet) {
    if (isOpen) _inputs[port]?.receive(packet);
  }

  /// Publishes the backend's [diagnostic]; a loss on an open input resets
  /// its stream state.
  void _onBackendDiagnostic(MidiDiagnostic diagnostic) {
    _report(diagnostic);
    final port = diagnostic.port;
    if (port == null || !isOpen) return;
    if (diagnostic.kind == MidiDiagnosticKind.queueOverflow ||
        diagnostic.kind == MidiDiagnosticKind.networkLoss) {
      _inputs[port]?.reset();
    }
  }

  /// Publishes [diagnostic].
  void _report(MidiDiagnostic diagnostic) => _bus.report(diagnostic);

  /// Reports that [action] on [port] failed with [error].
  void _nativeError(MidiPortId port, String action, Object error) => _report(
    MidiDiagnostic(
      kind: MidiDiagnosticKind.nativeError,
      port: port,
      cause: '$action failed: $error',
      time: clock.now(),
    ),
  );

  // ...........................................................................
  /// Throws a [StateError] unless the engine is open.
  void _checkOpen() {
    if (!isOpen) throw StateError('The engine is not open');
  }

  /// Throws unless the port [id] is known and of [direction].
  void _requirePort(MidiPortId id, MidiDirection direction) {
    _checkOpen();
    final port = _registry.port(id);
    if (port == null) throw MidiPortGone(id);
    if (port.direction != direction) {
      throw ArgumentError.value(id, 'id', 'Not an ${direction.name} port');
    }
  }

  /// Returns the pipeline of the open output [id], or throws.
  MidiOutputPipeline _openOutput(MidiPortId id) {
    _checkOpen();
    final pipeline = _outputs[id];
    if (pipeline != null) return pipeline;
    if (_registry.port(id) == null) throw MidiPortGone(id);
    throw StateError('The output $id is not open');
  }

  /// Returns the virtual port support of the backend, or throws.
  MidiVirtualPortsBackend _virtualPortsBackend() {
    _checkOpen();
    return backend.virtualPorts ??
        (throw const MidiUnsupported('Virtual ports'));
  }
}

// #############################################################################
/// The life cycle of a [MidiEngine].
enum _EngineState { created, opening, open, closing, closed }

// #############################################################################
/// The host a [MidiEngine] gives its backend.
final class _MidiEngineHost implements MidiBackendHost {
  _MidiEngineHost(this._engine);

  // ...........................................................................
  @override
  void portsChanged(List<MidiPortEvent> events) =>
      _engine._onPortsChanged(events);

  @override
  void received(MidiPortId port, MidiPacket packet) =>
      _engine._onReceived(port, packet);

  @override
  void diagnostic(MidiDiagnostic diagnostic) =>
      _engine._onBackendDiagnostic(diagnostic);

  // ...........................................................................
  @override
  MidiClock get clock => _engine.clock;

  // ...........................................................................
  final MidiEngine _engine;
}
