// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../clock/midi_clock.dart';
import 'midi_bounded_stream.dart';
import 'midi_input_options.dart';
import 'midi_input_session.dart';

// #############################################################################
/// Turns the packets of one input port into the events and packets of the
/// sessions open on it; `MidiEngine` keeps one pipeline per open input.
///
/// Sessions with the same parser limits share one MIDI 1.0 parser or UMP
/// decoder, so a fault in the stream is reported once. Sessions that also
/// share the delivery options share one translator, which keeps the
/// context of the port's stream.
final class MidiInputPipeline {
  /// Creates the pipeline of [port].
  ///
  /// - [clock] stamps the diagnostics.
  /// - [onDiagnostic] receives the faults of the stream and the queue
  ///   overflows of the sessions.
  /// - [onEmpty] is called when the last session closed by itself; the
  ///   engine then closes the port.
  MidiInputPipeline({
    required this._port,
    required this.clock,
    required this.onDiagnostic,
    required this.onEmpty,
  });

  // ...........................................................................
  /// Opens a session with [options].
  MidiInputSession open(MidiInputOptions options) {
    final session = _InputSession(this, options);
    _sessions.add(session);
    return session;
  }

  /// Feeds [packet], received on the port, to the sessions.
  void receive(MidiPacket packet) {
    for (final session in [..._rawSessions]) {
      session._addPacket(packet);
    }
    for (final stage in [..._stages.values]) {
      stage.add(packet);
    }
  }

  /// Drops partial messages, the last JR timestamp and the translation
  /// context, e.g. after a gap in the stream of the port.
  void reset() {
    for (final stage in _stages.values) {
      stage.reset();
    }
  }

  /// Takes over the changed description [port] of the port; a new raw
  /// form, protocol or group also resets the stream state like [reset].
  void update(MidiPortInfo port) {
    final previous = _port;
    _port = port;
    if (previous.capabilities.ump != port.capabilities.ump ||
        previous.protocol != port.protocol ||
        previous.group != port.group) {
      reset();
    }
  }

  // ...........................................................................
  /// Closes all sessions because the port disappeared; their streams
  /// complete after the values they queued.
  void end() => _finishAll(graceful: true);

  /// Closes all sessions at once because the engine closes; queued values
  /// are discarded.
  void close() => _finishAll(graceful: false);

  // ...........................................................................
  /// The port as it is now.
  MidiPortInfo get port => _port;

  /// Whether no session is open.
  bool get isEmpty => _sessions.isEmpty;

  /// Stamps the diagnostics.
  final MidiClock clock;

  /// Receives the faults of the stream and the queue overflows.
  final void Function(MidiDiagnostic diagnostic) onDiagnostic;

  /// Called when the last session closed by itself.
  final Future<void> Function() onEmpty;

  // ...........................................................................
  MidiPortInfo _port;
  final _sessions = <_InputSession>{};
  final _rawSessions = <_InputSession>{};
  final _stages = <_StageKey, _DecodeStage>{};

  /// Closes every session; [graceful] delivers the queued values first.
  void _finishAll({required bool graceful}) {
    final sessions = [..._sessions];
    _sessions.clear();
    _rawSessions.clear();
    _stages.clear();
    for (final session in sessions) {
      session._finish(graceful: graceful);
    }
  }

  /// Creates the event stream of [session] and attaches the session to the
  /// stage and the delivery of its options.
  MidiBoundedStream<MidiEvent> _attachEvents(_InputSession session) {
    final stream = _streamOf<MidiEvent>(session, 'events');
    if (session.isClosed) return stream..close();
    final options = session.options;
    final stage = _stages.putIfAbsent(
      _stageKey(options),
      () => _DecodeStage(this, _stageKey(options)),
    );
    final delivery = stage.deliveries.putIfAbsent(
      _deliveryKey(options),
      () => _Delivery(this, _deliveryKey(options)),
    );
    delivery.sessions.add(session);
    session._stage = stage;
    session._delivery = delivery;
    return stream;
  }

  /// Creates the packet stream of [session].
  MidiBoundedStream<MidiPacket> _attachPackets(_InputSession session) {
    final stream = _streamOf<MidiPacket>(session, 'packets');
    if (session.isClosed) return stream..close();
    _rawSessions.add(session);
    return stream;
  }

  /// Returns a bounded stream of [session] that reports its overflows as
  /// dropped [name].
  MidiBoundedStream<T> _streamOf<T>(_InputSession session, String name) {
    final capacity = session.options.queueCapacity;
    return MidiBoundedStream<T>(
      capacity: capacity,
      onOverflow: (dropped) => _issue(
        MidiDiagnosticKind.queueOverflow,
        'An input session dropped $dropped $name beyond its capacity of '
        '$capacity',
        count: dropped,
      ),
    );
  }

  /// Detaches [session], which closed by itself, and calls [onEmpty] after
  /// the last one.
  Future<void> _remove(_InputSession session) async {
    if (!_sessions.remove(session)) return;
    _rawSessions.remove(session);
    final stage = session._stage;
    final delivery = session._delivery;
    if (stage != null && delivery != null) {
      delivery.sessions.remove(session);
      if (delivery.sessions.isEmpty) stage.deliveries.remove(delivery.key);
      if (stage.deliveries.isEmpty) _stages.remove(stage.key);
    }
    if (_sessions.isEmpty) await onEmpty();
  }

  /// Reports a fault of [kind] with [cause] for the port.
  void _issue(MidiDiagnosticKind kind, String cause, {int count = 1}) =>
      onDiagnostic(
        MidiDiagnostic(
          kind: kind,
          port: _port.id,
          count: count,
          cause: cause,
          time: clock.now(),
        ),
      );

  /// Returns the parser limits of [options].
  static _StageKey _stageKey(MidiInputOptions options) => (
    maxSysExLength: options.maxSysExLength,
    maxSysExDuration: options.maxSysExDuration,
  );

  /// Returns the delivery options of [options].
  static _DeliveryKey _deliveryKey(MidiInputOptions options) => (
    deliverAs: options.deliverAs,
    noteOnZeroAsNoteOff: options.noteOnZeroAsNoteOff,
    flushDataEntryMsb: options.flushDataEntryMsb,
  );
}

// #############################################################################
/// The parser limits sessions share a decode stage by.
typedef _StageKey = ({int maxSysExLength, Duration? maxSysExDuration});

/// The delivery options sessions share a translator by.
typedef _DeliveryKey = ({
  MidiProtocol? deliverAs,
  bool noteOnZeroAsNoteOff,
  bool flushDataEntryMsb,
});

// #############################################################################
/// Parses or decodes the packets of a port and consumes the JR timestamps.
final class _DecodeStage {
  _DecodeStage(this._pipeline, this.key);

  // ...........................................................................
  /// Turns [packet] into events for the deliveries.
  void add(MidiPacket packet) {
    final events = <MidiEvent>[];
    switch (packet) {
      case MidiBytesPacket(:final bytes, :final time):
        final group = _pipeline.port.group;
        for (final decoded in _byteParser.add(bytes.bytes, time: time)) {
          _collect(events, decoded.message, decoded.time, group);
        }
      case MidiUmpPacket(:final words, :final time):
        for (final decoded in _umpDecoder.add(words, time: time)) {
          _collect(events, decoded.message, decoded.time, decoded.group);
        }
    }
    if (events.isEmpty) return;
    for (final delivery in [...deliveries.values]) {
      delivery.deliver(events);
    }
  }

  /// Drops the partial messages, the last JR timestamp and the translation
  /// context.
  void reset() {
    _parser?.reset();
    _decoder?.reset();
    _senderTime = null;
    for (final delivery in deliveries.values) {
      delivery.reset();
    }
  }

  // ...........................................................................
  /// The parser limits of the stage.
  final _StageKey key;

  /// The deliveries fed by the stage.
  final deliveries = <_DeliveryKey, _Delivery>{};

  // ...........................................................................
  final MidiInputPipeline _pipeline;
  MidiByteParser? _parser;
  UmpDecoder? _decoder;
  int? _senderTime;

  /// The parser of byte packets, created on first use.
  MidiByteParser get _byteParser => _parser ??= MidiByteParser(
    maxSysExLength: key.maxSysExLength,
    maxSysExDuration: key.maxSysExDuration,
    onIssue: _pipeline._issue,
  );

  /// The decoder of UMP packets, created on first use.
  UmpDecoder get _umpDecoder => _decoder ??= UmpDecoder(
    maxSysExLength: key.maxSysExLength,
    maxSysExDuration: key.maxSysExDuration,
    onIssue: _pipeline._issue,
  );

  /// Adds the event of [message] to [events]; a JR timestamp becomes the
  /// sender time of the following events, JR clocks and NOOPs vanish.
  void _collect(
    List<MidiEvent> events,
    MidiMessage message,
    MidiTime time,
    int? group,
  ) {
    switch (message) {
      case MidiJrTimestamp(time: final senderTime):
        _senderTime = senderTime;
      case MidiJrClock() || MidiNoop():
        break;
      default:
        events.add(
          MidiEvent(
            message: message,
            time: time,
            port: _pipeline.port.id,
            group: group,
            senderTime: _senderTime,
          ),
        );
    }
  }
}

// #############################################################################
/// Translates the events of a decode stage for the sessions that share
/// its delivery options.
final class _Delivery {
  _Delivery(this._pipeline, this.key);

  // ...........................................................................
  /// Translates [events] and hands them to the sessions.
  void deliver(List<MidiEvent> events) {
    final delivered = [
      for (final event in events)
        for (final message in _translate(event))
          identical(message, event.message)
              ? event
              : event.copyWith(message: message),
    ];
    if (delivered.isEmpty) return;
    for (final session in [...sessions]) {
      session._addEvents(delivered);
    }
  }

  /// Drops the translation context.
  void reset() => _up?.reset();

  // ...........................................................................
  /// The delivery options.
  final _DeliveryKey key;

  /// The sessions the delivery feeds.
  final sessions = <_InputSession>{};

  // ...........................................................................
  final MidiInputPipeline _pipeline;
  MidiTranslator1To2? _up;
  MidiTranslator2To1? _down;

  /// Returns the messages [event] becomes for the sessions.
  Iterable<MidiMessage> _translate(MidiEvent event) {
    final message = event.message;
    final translated = switch (message) {
      MidiChannelVoice2Message() when key.deliverAs == MidiProtocol.midi1 =>
        (_down ??= MidiTranslator2To1(
          onIssue: _pipeline._issue,
        )).translate(message),
      MidiChannelVoice1Message() when key.deliverAs == MidiProtocol.midi2 =>
        (_up ??= MidiTranslator1To2(
          flushDataEntryMsb: key.flushDataEntryMsb,
        )).translate(message, group: event.group ?? 0),
      _ => [message],
    };
    return key.noteOnZeroAsNoteOff ? translated.map(_noteOff) : translated;
  }

  /// Returns a Note Off for a MIDI 1.0 Note On with velocity 0, otherwise
  /// [message].
  static MidiMessage _noteOff(MidiMessage message) =>
      message is MidiNoteOn && message.isNoteOff
      ? MidiNoteOff(channel: message.channel, note: message.note)
      : message;
}

// #############################################################################
/// A session of [MidiInputPipeline].
final class _InputSession implements MidiInputSession {
  _InputSession(this._pipeline, this.options);

  // ...........................................................................
  @override
  Future<void> close() async {
    if (_isClosed) return;
    _finish(graceful: false);
    await _pipeline._remove(this);
  }

  // ...........................................................................
  @override
  final MidiInputOptions options;

  @override
  MidiPortInfo get port => _pipeline.port;

  @override
  Stream<MidiEvent> get events =>
      (_events ??= _pipeline._attachEvents(this)).stream;

  @override
  Stream<MidiPacket> get packets =>
      (_packets ??= _pipeline._attachPackets(this)).stream;

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> get done => _done.future;

  // ...........................................................................
  final MidiInputPipeline _pipeline;
  final _done = Completer<void>();
  MidiBoundedStream<MidiEvent>? _events;
  MidiBoundedStream<MidiPacket>? _packets;
  _DecodeStage? _stage;
  _Delivery? _delivery;
  bool _isClosed = false;

  /// Queues [events] for the event stream.
  void _addEvents(List<MidiEvent> events) => _events?.addAll(events);

  /// Queues [packet] for the packet stream.
  void _addPacket(MidiPacket packet) => _packets?.addAll([packet]);

  /// Closes the session; [graceful] delivers the queued values first.
  void _finish({required bool graceful}) {
    _isClosed = true;
    if (graceful) {
      _events?.end();
      _packets?.end();
    } else {
      _events?.close();
      _packets?.close();
    }
    _done.complete();
  }
}
