// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../clock/midi_clock.dart';
import '../error/midi_exception.dart';
import 'midi_note_tracker.dart';
import 'midi_output_session.dart';
import 'midi_panic.dart';
import 'midi_software_scheduler.dart';

// #############################################################################
/// Turns the messages of the sessions of one output port into packets of
/// the port's raw form and protocol and sends them on time;
/// `MidiEngine` keeps one pipeline per open output.
///
/// Byte ports get MIDI 1.0 bytes: MIDI 2.0 channel voice messages are
/// translated down, messages without a byte form dropped. UMP ports get
/// Universal MIDI Packets in the port's protocol: MIDI 1.0 channel voice
/// messages are translated up for a MIDI 2.0 port with the context of the
/// port's stream, MIDI 2.0 ones down for a MIDI 1.0 port, and System
/// Exclusive 8 and Mixed Data Sets need [MidiPortCapabilities.sysEx8].
/// Dropped messages are reported as [MidiDiagnosticKind.untranslatable].
///
/// Where packets for later wait depends on the port:
///
/// - With [MidiPortCapabilities.scheduledSend] and
///   [MidiPortCapabilities.cancelPending] the operating system gets them
///   at once; it times and discards them.
/// - With [MidiPortCapabilities.scheduledSend] only, the operating system
///   times them precisely but cannot discard what it holds. They wait in
///   the [scheduler] until [lookahead] before their time and stay
///   cancellable until then; a null [lookahead] hands them over at once.
/// - Without [MidiPortCapabilities.scheduledSend] they wait in the
///   [scheduler] until they are due.
final class MidiOutputPipeline {
  /// Creates the pipeline of [port].
  ///
  /// - [clock] the package clock the due times refer to.
  /// - [scheduler] holds the packets of ports without
  ///   [MidiPortCapabilities.scheduledSend] until they are due.
  /// - [send] hands a packet to the backend.
  /// - [cancelBackend] discards the packets the backend holds for a port.
  /// - [onDiagnostic] receives the dropped messages.
  /// - [onEmpty] is called when the last session closed by itself; the
  ///   engine then closes the port.
  /// - [flushDataEntryMsb] the alternate translation to MIDI 2.0, see
  ///   [MidiTranslator1To2].
  /// - [lookahead] how long before their time packets go to an operating
  ///   system that schedules but cannot discard; null for at once.
  MidiOutputPipeline({
    required this._port,
    required this.clock,
    required this.scheduler,
    required this.send,
    required this.cancelBackend,
    required this.onDiagnostic,
    required this.onEmpty,
    this.flushDataEntryMsb = false,
    this.lookahead,
  });

  // ...........................................................................
  /// Opens a session on the port.
  MidiOutputSession open() {
    final session = _OutputSession(this);
    _sessions.add(session);
    return session;
  }

  /// Sends [messages] in one packet at [at] on [group].
  ///
  /// The future completes when the port's queue accepted the packet.
  Future<void> sendMessages(
    Iterable<MidiMessage> messages, {
    MidiTime? at,
    int? group,
  }) {
    final target = _port.capabilities.ump ? group ?? _port.group : 0;
    final list = messages.toList();
    for (final message in list) {
      _tracker.track(message, group: target);
    }
    final packet = _encode(list, time: at ?? clock.now(), group: target);
    return packet == null ? Future.value() : _deliver(packet);
  }

  /// Sends the raw [packet] at its time; a packet of the other raw form is
  /// decoded and encoded for the port first.
  Future<void> sendPacket(MidiPacket packet) {
    if ((packet is MidiUmpPacket) == _port.capabilities.ump) {
      return _deliver(packet);
    }
    final converted = _encode(
      _decode(packet),
      time: packet.time,
      group: _port.group,
    );
    return converted == null ? Future.value() : _deliver(converted);
  }

  /// Discards the packets that wait for their due time, in the scheduler
  /// and, with [MidiPortCapabilities.cancelPending], in the backend.
  ///
  /// Returns the number of packets that still leave: those handed to an
  /// operating system that cannot discard them, due later than now.
  Future<int> cancelPending() async {
    scheduler.cancel(_port.id);
    if (_port.capabilities.cancelPending) {
      await cancelBackend(_port.id);
      _held.clear();
    }
    return _stillHeld().length;
  }

  /// Silences the port as [panic] describes, on the port's group and on
  /// every group with notes still on.
  ///
  /// When the operating system still holds packets it cannot discard, the
  /// panic messages are sent once more, one millisecond after the last of
  /// them.
  Future<void> panic(MidiPanic panic) async {
    final held = panic.cancelPending && await cancelPending() > 0
        ? _stillHeld().reduce((a, b) => a.isAfter(b) ? a : b)
        : null;
    final groups = _port.capabilities.ump
        ? {_port.group, ..._tracker.groups}
        : const {0};
    for (final group in groups) {
      final messages = panic.messages(activeNotes: _tracker.notesOf(group));
      await sendMessages(messages, group: group);
      if (held != null) {
        final after = held + const Duration(milliseconds: 1);
        await sendMessages(messages, at: after, group: group);
      }
    }
  }

  /// Takes note that the [scheduler] handed [packet] to the backend; an
  /// operating system that cannot discard holds it from now on.
  void handedOver(MidiPacket packet) {
    if (_isUncancellable) _hold(packet.time);
  }

  /// Takes over the changed description [port] of the port; a new raw form
  /// or protocol resets the translation context.
  void update(MidiPortInfo port) {
    final previous = _port;
    _port = port;
    if (previous.capabilities.ump != port.capabilities.ump ||
        previous.protocol != port.protocol) {
      _up?.reset();
    }
  }

  // ...........................................................................
  /// Closes all sessions because the port disappeared; their methods throw
  /// [MidiPortGone] from now on. The scheduled packets are discarded.
  void end() => _finishAll(gone: true);

  /// Closes all sessions because the engine closes. The scheduled packets
  /// are discarded.
  void close() => _finishAll(gone: false);

  // ...........................................................................
  /// The port as it is now.
  MidiPortInfo get port => _port;

  /// Whether no session is open.
  bool get isEmpty => _sessions.isEmpty;

  /// The package clock the due times refer to.
  final MidiClock clock;

  /// Holds the packets until they are due.
  final MidiSoftwareScheduler scheduler;

  /// Hands a packet to the backend.
  final Future<void> Function(MidiPortId port, MidiPacket packet) send;

  /// Discards the packets the backend holds for a port.
  final Future<void> Function(MidiPortId port) cancelBackend;

  /// Receives the dropped messages.
  final void Function(MidiDiagnostic diagnostic) onDiagnostic;

  /// Called when the last session closed by itself.
  final Future<void> Function() onEmpty;

  /// Whether the translation to MIDI 2.0 also sends a Data Entry MSB
  /// without LSB.
  final bool flushDataEntryMsb;

  /// How long before their time packets go to an operating system that
  /// schedules but cannot discard; null hands them over at once.
  final Duration? lookahead;

  // ...........................................................................
  MidiPortInfo _port;
  final _sessions = <_OutputSession>{};
  final _tracker = MidiNoteTracker();

  /// The due times of the packets handed to an operating system that
  /// cannot discard them.
  final _held = <MidiTime>[];
  MidiTranslator1To2? _up;
  MidiTranslator2To1? _down;

  /// The translator to MIDI 2.0, created on first use.
  MidiTranslator1To2 get _toMidi2 =>
      _up ??= MidiTranslator1To2(flushDataEntryMsb: flushDataEntryMsb);

  /// The translator to MIDI 1.0, created on first use.
  MidiTranslator2To1 get _toMidi1 =>
      _down ??= MidiTranslator2To1(onIssue: _issue);

  /// Returns the packet of [messages] due at [time] for [group], or null
  /// when no message is left.
  MidiPacket? _encode(
    List<MidiMessage> messages, {
    required MidiTime time,
    required int group,
  }) {
    if (_port.capabilities.ump) {
      final words = [
        for (final message in messages)
          for (final translated in _forUmp(message, group))
            for (final ump in UmpEncoder.encode(translated, group: group))
              ...ump.words,
      ];
      return words.isEmpty ? null : MidiUmpPacket(words: words, time: time);
    }
    final bytes = [
      for (final message in messages)
        for (final translated in _forBytes(message)) ...?_bytesOf(translated),
    ];
    return bytes.isEmpty
        ? null
        : MidiBytesPacket(bytes: MidiBytes(bytes), time: time);
  }

  /// Returns [message] in the protocol of a UMP port.
  List<MidiMessage> _forUmp(MidiMessage message, int group) =>
      switch (message) {
        MidiChannelVoice1Message() when _port.protocol == MidiProtocol.midi2 =>
          _toMidi2.translate(message, group: group),
        MidiChannelVoice2Message() when _port.protocol == MidiProtocol.midi1 =>
          _toMidi1.translate(message),
        MidiSysEx8() || MidiMixedDataSet() when !_port.capabilities.sysEx8 =>
          _drop(message, 'needs a port with System Exclusive 8 support'),
        _ => [message],
      };

  /// Returns [message] in the MIDI 1.0 protocol for a byte port.
  List<MidiMessage> _forBytes(MidiMessage message) =>
      message is MidiChannelVoice2Message
      ? _toMidi1.translate(message)
      : [message];

  /// Returns the bytes of [message], or reports it and returns null when it
  /// has no byte form.
  List<int>? _bytesOf(MidiMessage message) {
    final bytes = MidiByteEncoder.encode(message);
    if (bytes == null) _drop(message, 'has no MIDI 1.0 byte form');
    return bytes?.bytes;
  }

  /// Returns the messages of a [packet] of the other raw form.
  List<MidiMessage> _decode(MidiPacket packet) => switch (packet) {
    MidiBytesPacket(:final bytes) => [
      for (final decoded in MidiByteParser(onIssue: _issue).add(bytes.bytes))
        decoded.message,
    ],
    MidiUmpPacket(:final words) => [
      for (final decoded in UmpDecoder(onIssue: _issue).add(words))
        decoded.message,
    ],
  };

  /// Whether the operating system schedules but cannot discard.
  bool get _isUncancellable =>
      _port.capabilities.scheduledSend && !_port.capabilities.cancelPending;

  /// Returns how long before its time a packet has to reach the backend,
  /// or null when the backend takes it at once.
  Duration? get _lead {
    final capabilities = _port.capabilities;
    if (!capabilities.scheduledSend) return Duration.zero;
    return capabilities.cancelPending ? null : lookahead;
  }

  /// Sends [packet] now or hands it to the scheduler.
  Future<void> _deliver(MidiPacket packet) {
    final lead = _lead;
    if (lead != null) {
      if (packet.time.isAfter(clock.now() + lead)) {
        scheduler.schedule(_port.id, packet, lead: lead);
        return Future.value();
      }
      scheduler.dispatchDue(port: _port.id);
    }
    if (_isUncancellable) _hold(packet.time);
    return send(_port.id, packet);
  }

  /// Remembers a packet due at [time] that the operating system cannot
  /// discard.
  void _hold(MidiTime time) {
    if (time.isAfter(clock.now())) _held.add(time);
  }

  /// Returns the due times of the held packets that did not leave yet.
  List<MidiTime> _stillHeld() {
    final now = clock.now();
    _held.removeWhere((time) => !time.isAfter(now));
    return _held;
  }

  /// Reports that [message] was dropped because it [reason].
  List<MidiMessage> _drop(MidiMessage message, String reason) {
    _issue(MidiDiagnosticKind.untranslatable, '${message.runtimeType} $reason');
    return const [];
  }

  /// Reports a fault of [kind] with [cause] for the port.
  void _issue(MidiDiagnosticKind kind, String cause) => onDiagnostic(
    MidiDiagnostic(kind: kind, port: _port.id, cause: cause, time: clock.now()),
  );

  /// Closes every session; [gone] marks the port as disappeared.
  void _finishAll({required bool gone}) {
    scheduler.cancel(_port.id);
    final sessions = [..._sessions];
    _sessions.clear();
    for (final session in sessions) {
      session._finish(gone: gone);
    }
  }

  /// Detaches [session], which closed by itself; after the last one the
  /// pending packets are discarded and [onEmpty] is called.
  Future<void> _remove(_OutputSession session) async {
    if (!_sessions.remove(session) || _sessions.isNotEmpty) return;
    try {
      await cancelPending();
    } on Object catch (error) {
      _issue(
        MidiDiagnosticKind.nativeError,
        'Discarding the pending packets failed: $error',
      );
    }
    await onEmpty();
  }
}

// #############################################################################
/// A session of [MidiOutputPipeline].
final class _OutputSession implements MidiOutputSession {
  _OutputSession(this._pipeline);

  // ...........................................................................
  @override
  Future<void> send(MidiMessage message, {MidiTime? at, int? group}) async {
    _check();
    await _pipeline.sendMessages([message], at: at, group: group);
  }

  @override
  Future<void> sendAll(
    Iterable<MidiMessage> messages, {
    MidiTime? at,
    int? group,
  }) async {
    _check();
    await _pipeline.sendMessages(messages, at: at, group: group);
  }

  @override
  Future<void> sendPacket(MidiPacket packet) async {
    _check();
    await _pipeline.sendPacket(packet);
  }

  // ...........................................................................
  @override
  Future<int> cancelPending() async {
    _check();
    return _pipeline.cancelPending();
  }

  @override
  Future<void> panic({MidiPanic panic = const MidiPanic()}) async {
    _check();
    await _pipeline.panic(panic);
  }

  // ...........................................................................
  @override
  Future<void> close() async {
    if (_isClosed) return;
    _finish(gone: false);
    await _pipeline._remove(this);
  }

  // ...........................................................................
  @override
  MidiPortInfo get port => _pipeline.port;

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> get done => _done.future;

  // ...........................................................................
  final MidiOutputPipeline _pipeline;
  final _done = Completer<void>();
  bool _isClosed = false;
  bool _isGone = false;

  /// Throws when the session can no longer send.
  void _check() {
    if (_isGone) throw MidiPortGone(_pipeline.port.id);
    if (_isClosed) {
      throw StateError('The output session of ${_pipeline.port.id} is closed');
    }
  }

  /// Closes the session; [gone] marks the port as disappeared.
  void _finish({required bool gone}) {
    _isClosed = true;
    _isGone = gone;
    _done.complete();
  }
}
