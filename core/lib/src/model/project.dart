// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

enum ProjectStatus {
  draft('draft'),
  inReview('in_review'),
  finalized('finalized');

  const ProjectStatus(this.wire);
  final String wire;

  static ProjectStatus fromWire(String wire) =>
      ProjectStatus.values.firstWhere((v) => v.wire == wire);
}

/// One rated voltage of the panel, with system context (spec §2.1).
@immutable
class RatedVoltage {
  const RatedVoltage({
    required this.volts,
    required this.system,
    required this.slashRatingContext,
  });

  final double volts;
  final VoltageSystem system;

  /// Whether slash-rated equipment context applies at this voltage.
  /// Applicability parameters are owner-configured in the registry
  /// (voltage-validation rule), not decided here.
  final bool slashRatingContext;

  Map<String, Object?> toJson() => {
        'volts': volts,
        'system': system.wire,
        'slash_rating_context': slashRatingContext,
      };

  factory RatedVoltage.fromJson(Map<String, Object?> json) => RatedVoltage(
        volts: (json['volts'] as num).toDouble(),
        system: VoltageSystem.fromWire(json['system'] as String),
        slashRatingContext: json['slash_rating_context'] as bool,
      );

  /// Stable key for per-voltage rollup results.
  String get key => '${volts}V_${system.wire}';

  @override
  bool operator ==(Object other) =>
      other is RatedVoltage &&
      other.volts == volts &&
      other.system == system &&
      other.slashRatingContext == slashRatingContext;

  @override
  int get hashCode => Object.hash(volts, system, slashRatingContext);
}

/// One SCCR determination effort (spec §2.1 Project/Panel).
///
/// Invariant (spec §2.2): a finalized project is immutable. The core enforces
/// this via [assertEditable]; persistence layers must call it before writing.
@immutable
class Project {
  const Project({
    required this.meta,
    required this.shopId,
    required this.name,
    required this.status,
    required this.ratedVoltages,
    this.customer,
    this.panelNumber,
    this.revision,
    this.phases,
    this.frequencyHz,
    this.enclosureRef,
    this.finalizedSnapshotRef,
  });

  final EntityMeta meta;
  final Id shopId;
  final String name;
  final String? customer;
  final String? panelNumber;
  final String? revision;
  final List<RatedVoltage> ratedVoltages;
  final int? phases;
  final double? frequencyHz;

  /// Free-text enclosure reference.
  final String? enclosureRef;

  final ProjectStatus status;

  /// Set at finalization; points at the frozen snapshot record
  /// (data + registry versions + report PDF hash).
  final String? finalizedSnapshotRef;

  bool get isFinalized => status == ProjectStatus.finalized;

  /// Throws [StateError] if this project may no longer be edited.
  /// Post-finalization changes require a new revision (spec §2.1).
  void assertEditable() {
    if (isFinalized) {
      throw StateError(
        'Project ${meta.id} is finalized and immutable. '
        'Create a new revision to make changes.',
      );
    }
  }

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'shop_id': shopId,
        'name': name,
        'customer': customer,
        'panel_number': panelNumber,
        'revision': revision,
        'rated_voltages': ratedVoltages.map((v) => v.toJson()).toList(),
        'phases': phases,
        'frequency_hz': frequencyHz,
        'enclosure_ref': enclosureRef,
        'status': status.wire,
        'finalized_snapshot_ref': finalizedSnapshotRef,
      };

  factory Project.fromJson(Map<String, Object?> json) => Project(
        meta: EntityMeta.fromJson(json),
        shopId: json['shop_id'] as Id,
        name: json['name'] as String,
        customer: json['customer'] as String?,
        panelNumber: json['panel_number'] as String?,
        revision: json['revision'] as String?,
        ratedVoltages: (json['rated_voltages'] as List)
            .map((v) =>
                RatedVoltage.fromJson((v as Map).cast<String, Object?>()))
            .toList(),
        phases: json['phases'] as int?,
        frequencyHz: (json['frequency_hz'] as num?)?.toDouble(),
        enclosureRef: json['enclosure_ref'] as String?,
        status: ProjectStatus.fromWire(json['status'] as String),
        finalizedSnapshotRef: json['finalized_snapshot_ref'] as String?,
      );
}
