// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Regenerates data/registry_seeds/registry_seed.json from the shipped
// registry scaffold, so the seed file can never drift from the code.
// Run from core/: dart run tool/generate_registry_seed.dart
// Kept in sync by a test in core/test/model_test.dart-adjacent suite.

import 'dart:convert';
import 'dart:io';

import 'package:faultcorral_core/faultcorral_core.dart';

void main() {
  final json = const JsonEncoder.withIndent('  ')
      .convert(RulesRegistry.scaffold().toJson());
  File('../data/registry_seeds/registry_seed.json')
      .writeAsStringSync('$json\n');
  stdout.writeln('registry seed regenerated.');
}
