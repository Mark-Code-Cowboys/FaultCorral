// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

enum CircuitKind {
  feeder('feeder'),
  branch('branch'),
  sub('sub');

  const CircuitKind(this.wire);
  final String wire;

  static CircuitKind fromWire(String wire) =>
      CircuitKind.values.firstWhere((v) => v.wire == wire);
}

/// Node in the panel's power-circuit tree (spec §2.1).
///
/// The tree matters: series-combination and protective-device relationships
/// are parent-path dependent, so the engine walks parent links when deciding
/// whether a combo's upstream device is actually on a component's path.
@immutable
class Circuit {
  const Circuit({
    required this.meta,
    required this.projectId,
    required this.kind,
    required this.label,
    this.parentCircuitId,
    this.upstreamProtectiveDeviceComponentId,
    this.notes,
  });

  final EntityMeta meta;
  final Id projectId;

  /// Null means this is the incoming feeder (tree root).
  final Id? parentCircuitId;

  final CircuitKind kind;
  final String label;

  /// Component acting as this circuit's upstream protective device.
  final Id? upstreamProtectiveDeviceComponentId;

  final String? notes;

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'project_id': projectId,
        'parent_circuit_id': parentCircuitId,
        'kind': kind.wire,
        'label': label,
        'upstream_protective_device_component_id':
            upstreamProtectiveDeviceComponentId,
        'notes': notes,
      };

  factory Circuit.fromJson(Map<String, Object?> json) => Circuit(
        meta: EntityMeta.fromJson(json),
        projectId: json['project_id'] as Id,
        parentCircuitId: json['parent_circuit_id'] as Id?,
        kind: CircuitKind.fromWire(json['kind'] as String),
        label: json['label'] as String,
        upstreamProtectiveDeviceComponentId:
            json['upstream_protective_device_component_id'] as Id?,
        notes: json['notes'] as String?,
      );
}
