// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Banned-vocabulary lint (spec §0.1). FaultCorral is a documentation aid,
// never an authority: user-facing strings must not claim that anything is
// compliant, certified, approved, verified, guaranteed, or that it "meets
// UL 508A" or "passes". CI fails when these appear in user-facing surfaces:
//
//   - string literals in core/lib and app/lib Dart code
//   - report templates and markdown under report/
//
// legal/ is excluded: that text is attorney-owned and legitimately negates
// these words. docs/ and README are developer-facing.
//
// Escape hatch, sparingly and with a reason: a comment line containing
// `lint:allow-banned-vocab` suppresses findings from that line until the
// next blank line. Every use is listed in the lint output for owner review.

import 'dart:io';

final bannedPatterns = <RegExp>[
  RegExp(r'\bcomplian(?:t|ce)\b', caseSensitive: false),
  RegExp(r'\bcertif(?:y|ies|ied|ications?)\b', caseSensitive: false),
  RegExp(r'\bapprov(?:e|es|ed|als?)\b', caseSensitive: false),
  RegExp(r'\bverif(?:y|ies|ied|ications?)\b', caseSensitive: false),
  RegExp(r'\bguarantee[ds]?\b', caseSensitive: false),
  RegExp(r'\bpass(?:es|ed)?\b', caseSensitive: false),
  RegExp(r'meets\s+UL\s*508A', caseSensitive: false),
];

const allowMarker = 'lint:allow-banned-vocab';

final quotedSegment = RegExp("'(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\"");

Iterable<File> filesUnder(String dir, bool Function(String path) keep) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => keep(f.path) && !f.path.contains('.dart_tool'));
}

void main() {
  final violations = <String>[];
  final allowances = <String>[];

  void scan(File file, {required bool dartStringsOnly}) {
    final lines = file.readAsLinesSync();
    var allowedUntilBlank = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) allowedUntilBlank = false;
      if (line.contains(allowMarker)) {
        allowedUntilBlank = true;
        allowances.add('${file.path}:${i + 1}');
        continue;
      }
      final haystacks = dartStringsOnly
          ? quotedSegment.allMatches(line).map((m) => m.group(0)!)
          : [line];
      for (final text in haystacks) {
        for (final pattern in bannedPatterns) {
          final m = pattern.firstMatch(text);
          if (m != null) {
            if (allowedUntilBlank) {
              allowances.add('${file.path}:${i + 1} ("${m.group(0)}")');
            } else {
              violations.add(
                '${file.path}:${i + 1} banned term "${m.group(0)}" in: '
                '${line.trim()}',
              );
            }
          }
        }
      }
    }
  }

  for (final file in [
    ...filesUnder('core/lib', (p) => p.endsWith('.dart')),
    ...filesUnder('app/lib', (p) => p.endsWith('.dart')),
  ]) {
    scan(file, dartStringsOnly: true);
  }
  for (final file in filesUnder(
    'report',
    (p) => p.endsWith('.md') || p.endsWith('.txt'),
  )) {
    scan(file, dartStringsOnly: false);
  }
  for (final file in filesUnder('report', (p) => p.endsWith('.dart'))) {
    scan(file, dartStringsOnly: true);
  }

  if (allowances.isNotEmpty) {
    stdout.writeln(
      'banned-vocab: ${allowances.length} allowance(s) '
      '(review at each phase gate):',
    );
    for (final a in allowances) {
      stdout.writeln('  allowed: $a');
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln(
      'banned-vocab: FAIL — the app must never claim authority '
      '(spec §0.1):',
    );
    for (final v in violations) {
      stderr.writeln('  $v');
    }
    exit(1);
  }
  stdout.writeln('banned-vocab: OK');
}
