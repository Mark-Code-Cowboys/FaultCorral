// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import '../model/common.dart';

/// Lifecycle of a registry rule (spec §3.1). Everything ships `unverified`;
/// only the owner flips a rule to `verified` after checking it against his
/// licensed copy of the standard. The engine refuses to finalize while any
/// fired rule is still `unverified`.
enum RuleStatus {
  // lint:allow-banned-vocab — wire tokens for the owner sign-off lifecycle,
  // not user-facing claims about the panel.
  unverified('unverified'),
  verified('verified'),
  disabled('disabled');

  const RuleStatus(this.wire);
  final String wire;

  static RuleStatus fromWire(String wire) =>
      RuleStatus.values.firstWhere((v) => v.wire == wire);
}

/// One rule in the registry: data plus a small pure evaluator keyed by [id]
/// (spec §3.1). Descriptions are the owner's own words — never standard
/// text. [clausePointer] is a citation pointer the owner fills in; the app
/// never asserts anything about clause content.
@immutable
class RuleRegistryEntry {
  const RuleRegistryEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    required this.version,
    this.clausePointer,
    this.verifiedBy,
    this.verifiedDate,
    this.params = const {},
  });

  final String id;
  final String name;
  final String description;
  final String? clausePointer;
  final RuleStatus status;
  final Id? verifiedBy;
  final DateTime? verifiedDate;

  /// Bumped on any change to the rule's data or parameters.
  final int version;

  /// Rule-specific parameters (numeric thresholds, category applicability…).
  /// Owner-populated; empty at ship.
  final Map<String, Object?> params;

  bool get isVerified => status == RuleStatus.verified;
  bool get isDisabled => status == RuleStatus.disabled;

  RuleRegistryEntry copyWith({
    RuleStatus? status,
    Id? verifiedBy,
    DateTime? verifiedDate,
    int? version,
    Map<String, Object?>? params,
    String? clausePointer,
    String? description,
  }) =>
      RuleRegistryEntry(
        id: id,
        name: name,
        description: description ?? this.description,
        clausePointer: clausePointer ?? this.clausePointer,
        status: status ?? this.status,
        verifiedBy: verifiedBy ?? this.verifiedBy,
        verifiedDate: verifiedDate ?? this.verifiedDate,
        version: version ?? this.version,
        params: params ?? this.params,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'clause_pointer': clausePointer,
        'status': status.wire,
        'verified_by': verifiedBy,
        'verified_date': verifiedDate?.toUtc().toIso8601String(),
        'version': version,
        'params': params,
      };

  factory RuleRegistryEntry.fromJson(Map<String, Object?> json) =>
      RuleRegistryEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        clausePointer: json['clause_pointer'] as String?,
        status: RuleStatus.fromWire(json['status'] as String),
        verifiedBy: json['verified_by'] as Id?,
        verifiedDate: json['verified_date'] == null
            ? null
            : DateTime.parse(json['verified_date'] as String),
        version: json['version'] as int,
        params: (json['params'] as Map? ?? {}).cast<String, Object?>(),
      );
}
