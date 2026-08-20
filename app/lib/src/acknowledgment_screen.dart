// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Mandatory first-run acknowledgment (spec §0.4). Mechanics are fixed:
// two checkboxes, both unchecked by default, both required to proceed —
// no pre-check, no "skip for now". Wording is the spec placeholder pending
// attorney review; the version string lives with the text so any material
// change re-presents the screen to every user.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

/// Must match legal/FIRST_RUN_ACKNOWLEDGMENT_DRAFT.md.
const acknowledgmentTextVersion = '0.1.0-draft';

// lint:allow-banned-vocab — spec §0.4 placeholder wording: the text NEGATES
// authority claims ("does not ... verify, or certify"); attorney will supply
// final language. Version-locked to acknowledgmentTextVersion above.
const checkbox1Text = '[[ATTORNEY REVIEW REQUIRED]] I understand FaultCorral '
    'is a documentation aid, not an authority. It does not determine, verify, '
    'or certify any rating or compliance.';
const checkbox2Text = '[[ATTORNEY REVIEW REQUIRED]] I accept final '
    'responsibility and liability for all values entered, all determinations '
    'made, and all documentation produced using this tool.';

class AcknowledgmentScreen extends StatefulWidget {
  const AcknowledgmentScreen({
    super.key,
    required this.gate,
    required this.onAccepted,
    this.userId = 'user-local',
  });

  final AcknowledgmentGate gate;
  final ValueChanged<AcknowledgmentRecord> onAccepted;
  final String userId;

  @override
  State<AcknowledgmentScreen> createState() => _AcknowledgmentScreenState();
}

class _AcknowledgmentScreenState extends State<AcknowledgmentScreen> {
  // Both unchecked by default — never pre-checked (spec §0.4).
  bool _understoodTool = false;
  bool _acceptedResponsibility = false;

  bool get _canProceed => _understoodTool && _acceptedResponsibility;

  void _accept() {
    final now = DateTime.now().toUtc();
    widget.onAccepted(
      AcknowledgmentRecord(
        id: 'ack-${now.microsecondsSinceEpoch}',
        userId: widget.userId,
        textVersion: widget.gate.currentTextVersion,
        appVersion: appVersion,
        acceptedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before you begin',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'FaultCorral records these acknowledgments per user, with '
                  'the text version, app version, and timestamp.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                CheckboxListTile(
                  value: _understoodTool,
                  onChanged: (v) =>
                      setState(() => _understoodTool = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(checkbox1Text),
                ),
                CheckboxListTile(
                  value: _acceptedResponsibility,
                  onChanged: (v) =>
                      setState(() => _acceptedResponsibility = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(checkbox2Text),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    // Disabled until BOTH boxes are checked; there is no
                    // skip path by design (spec §0.4).
                    onPressed: _canProceed ? _accept : null,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
