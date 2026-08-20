// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Checks that every Dart source file starts with the Code Cowboys LLC
// copyright header (spec §7 Phase 0: license headers).

import 'dart:io';

const marker = 'Code Cowboys LLC';
const roots = ['core/lib', 'core/test', 'app/lib', 'report', 'tool'];

void main() {
  final missing = <String>[];
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.contains('.dart_tool')) {
        continue;
      }
      final head = file.readAsLinesSync().take(3).join('\n');
      if (!head.contains(marker)) missing.add(file.path);
    }
  }
  if (missing.isNotEmpty) {
    stderr.writeln('license-header: FAIL — missing header in:');
    for (final path in missing) {
      stderr.writeln('  $path');
    }
    exit(1);
  }
  stdout.writeln('license-header: OK');
}
