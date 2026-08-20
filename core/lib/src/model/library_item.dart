// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';
import 'component.dart';

/// A reusable catalog entry in the shop library (spec §2.1).
///
/// Library items are versioned; projects pin the version they used, so
/// deleting or editing a library item never mutates historical projects
/// (spec §2.2 invariant). Default attested data still carries source,
/// citation, and attester per field — the library is a convenience, not
/// an authority.
@immutable
class LibraryItem {
  const LibraryItem({
    required this.meta,
    required this.shopId,
    required this.manufacturer,
    required this.partNumber,
    required this.category,
    required this.version,
    this.categoryOtherLabel,
    this.defaultVoltageRating = const AttestedValue<VoltageRating>.empty(),
    this.defaultSccrKa = const AttestedValue<double>.empty(),
    this.defaultInterruptingRatingKa = const AttestedValue<double>.empty(),
    this.defaultCurrentLimiting,
    this.deleted = false,
  });

  final EntityMeta meta;
  final Id shopId;
  final String manufacturer;
  final String partNumber;
  final ComponentCategory category;
  final String? categoryOtherLabel;

  /// Monotonically increasing; bumped on every edit.
  final int version;

  final AttestedValue<VoltageRating> defaultVoltageRating;
  final AttestedValue<double> defaultSccrKa;
  final AttestedValue<double> defaultInterruptingRatingKa;
  final bool? defaultCurrentLimiting;

  /// Soft delete only — historical projects keep their pinned versions.
  final bool deleted;

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'shop_id': shopId,
        'manufacturer': manufacturer,
        'part_number': partNumber,
        'category': category.wire,
        'category_other_label': categoryOtherLabel,
        'version': version,
        'default_voltage_rating':
            defaultVoltageRating.toJson((v) => v.toJson()),
        'default_sccr_ka': defaultSccrKa.toJson((v) => v),
        'default_interrupting_rating_ka':
            defaultInterruptingRatingKa.toJson((v) => v),
        'default_current_limiting': defaultCurrentLimiting,
        'deleted': deleted,
      };

  factory LibraryItem.fromJson(Map<String, Object?> json) => LibraryItem(
        meta: EntityMeta.fromJson(json),
        shopId: json['shop_id'] as Id,
        manufacturer: json['manufacturer'] as String,
        partNumber: json['part_number'] as String,
        category: ComponentCategory.fromWire(json['category'] as String),
        categoryOtherLabel: json['category_other_label'] as String?,
        version: json['version'] as int,
        defaultVoltageRating: AttestedValue.fromJson(
          (json['default_voltage_rating'] as Map).cast<String, Object?>(),
          (raw) => VoltageRating.fromJson((raw as Map).cast<String, Object?>()),
        ),
        defaultSccrKa: AttestedValue.fromJson(
          (json['default_sccr_ka'] as Map).cast<String, Object?>(),
          (raw) => (raw as num).toDouble(),
        ),
        defaultInterruptingRatingKa: AttestedValue.fromJson(
          (json['default_interrupting_rating_ka'] as Map)
              .cast<String, Object?>(),
          (raw) => (raw as num).toDouble(),
        ),
        defaultCurrentLimiting: json['default_current_limiting'] as bool?,
        deleted: json['deleted'] as bool? ?? false,
      );
}
