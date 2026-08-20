// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:flutter/material.dart';

/// "Why this effective value" per component (spec §3.2 explainability).
void showTraceView(BuildContext context, RollupResult result) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Per-component value traces'),
      content: SizedBox(
        width: 640,
        height: 480,
        child: ListView(
          children: [
            for (final trace in result.traces) ...[
              Text(
                '${trace.tag} — effective '
                '${trace.effectiveSccrKa?.toStringAsFixed(1) ?? 'UNRATED'}'
                '${trace.effectiveSccrKa != null ? ' kA' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final step in trace.steps)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text(
                    '• ${step.description}'
                    '${step.ruleId != null ? '  [rule: ${step.ruleId}]' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    ),
  );
}
