// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Phase 0 stub: boots straight into the mandatory first-run acknowledgment
// flow (spec §0.4). Real navigation, persistence wiring (SQLite), and the
// project workspace land in Phase 1.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:flutter/material.dart';

import 'src/acknowledgment_screen.dart';

const appVersion = '0.0.1-phase0';

void main() {
  runApp(const FaultCorralApp());
}

class FaultCorralApp extends StatelessWidget {
  const FaultCorralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaultCorral',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6D4C2F),
        useMaterial3: true,
      ),
      // Phase 0: no persistence yet, so the gate always presents. Phase 1
      // loads stored AcknowledgmentRecords and consults AcknowledgmentGate.
      home: AcknowledgmentScreen(
        gate: const AcknowledgmentGate(
          currentTextVersion: acknowledgmentTextVersion,
        ),
        onAccepted: (record) {
          // TODO(phase-1): persist record + audit event, then enter the app.
          debugPrint('acknowledgment accepted: ${record.toJson()}');
        },
      ),
    );
  }
}
