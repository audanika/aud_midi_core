// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

// #############################################################################
/// Creates a one-shot timer that calls [callback] once [duration] has
/// passed.
///
/// `Timer.new` is the real implementation; `MidiFakeTimers.create` lets
/// tests move time by hand.
typedef MidiTimerFactory =
    Timer Function(Duration duration, void Function() callback);
