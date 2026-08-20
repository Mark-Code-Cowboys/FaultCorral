// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'dart:convert';
import 'dart:io';

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:test/test.dart';

void main() {
  test('shipped registry seed matches the code scaffold', () {
    final expected = const JsonEncoder.withIndent('  ')
        .convert(RulesRegistry.scaffold().toJson());
    final onDisk =
        File('../data/registry_seeds/registry_seed.json').readAsStringSync();
    expect(onDisk.trim(), expected.trim(),
        reason: 'Run: (cd core && dart run tool/generate_registry_seed.dart)');
  });
}
