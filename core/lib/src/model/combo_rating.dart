// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

/// One side of a tested series combination: how the manufacturer identifies
/// the device (spec §2.1 ComboRating).
@immutable
class DeviceSpec {
  const DeviceSpec({
    required this.manufacturer,
    required this.partOrFamily,
    this.classOrSize,
  });

  final String manufacturer;
  final String partOrFamily;
  final String? classOrSize;

  Map<String, Object?> toJson() => {
        'manufacturer': manufacturer,
        'part_or_family': partOrFamily,
        'class_or_size': classOrSize,
      };

  factory DeviceSpec.fromJson(Map<String, Object?> json) => DeviceSpec(
        manufacturer: json['manufacturer'] as String,
        partOrFamily: json['part_or_family'] as String,
        classOrSize: json['class_or_size'] as String?,
      );
}

/// A manufacturer-published tested series combination, entered and attested
/// by the user (spec §2.1). Shop-scoped; a curated global catalog is a
/// Phase 3 concern.
///
/// The engine may use a combo to elevate a downstream component's effective
/// SCCR only under the owner-configured series-combination rule (spec §3.1
/// rule 4), which requires the upstream device on the circuit path, voltage
/// limits holding, and full attestation.
@immutable
class ComboRating {
  const ComboRating({
    required this.meta,
    required this.shopId,
    required this.upstream,
    required this.downstream,
    required this.testedSccrKa,
    required this.voltageLimitVolts,
    required this.citation,
    required this.attestation,
  });

  final EntityMeta meta;
  final Id shopId;
  final DeviceSpec upstream;
  final DeviceSpec downstream;
  final double testedSccrKa;
  final double voltageLimitVolts;

  /// Source document + date, as supplied by the user.
  final String citation;
  final Attestation attestation;

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'shop_id': shopId,
        'upstream': upstream.toJson(),
        'downstream': downstream.toJson(),
        'tested_sccr_ka': testedSccrKa,
        'voltage_limit_volts': voltageLimitVolts,
        'citation': citation,
        'attestation': attestation.toJson(),
      };

  factory ComboRating.fromJson(Map<String, Object?> json) => ComboRating(
        meta: EntityMeta.fromJson(json),
        shopId: json['shop_id'] as Id,
        upstream: DeviceSpec.fromJson(
            (json['upstream'] as Map).cast<String, Object?>()),
        downstream: DeviceSpec.fromJson(
            (json['downstream'] as Map).cast<String, Object?>()),
        testedSccrKa: (json['tested_sccr_ka'] as num).toDouble(),
        voltageLimitVolts: (json['voltage_limit_volts'] as num).toDouble(),
        citation: json['citation'] as String,
        attestation: Attestation.fromJson(
            (json['attestation'] as Map).cast<String, Object?>()),
      );
}
