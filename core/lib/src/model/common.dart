// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

/// Opaque entity identifier. Generation strategy is the app's concern;
/// the core only requires uniqueness within a shop.
typedef Id = String;

/// Who entered/edited a value, and when. Captured at entry and at every edit
/// (spec §0.3). The app layer is responsible for stamping these; the core
/// treats a missing attestation as incomplete data.
@immutable
class Attestation {
  const Attestation({required this.userId, required this.timestamp});

  final Id userId;
  final DateTime timestamp;

  Map<String, Object?> toJson() => {
        'user_id': userId,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };

  factory Attestation.fromJson(Map<String, Object?> json) => Attestation(
        userId: json['user_id'] as Id,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is Attestation &&
      other.userId == userId &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(userId, timestamp);
}

/// Where an attested value came from (spec §0.3).
enum SourceType {
  marked('marked'),
  datasheet('datasheet'),
  assumedDefault('assumed_default'),
  seriesCombination('series_combination'),
  other('other');

  const SourceType(this.wire);
  final String wire;

  static SourceType fromWire(String wire) =>
      SourceType.values.firstWhere((v) => v.wire == wire);
}

/// A value the user supplied together with its provenance. The core never
/// fabricates one of these; a component with an incomplete [AttestedValue]
/// for SCCR is UNRATED and blocks finalization.
@immutable
class AttestedValue<T> {
  const AttestedValue({
    this.value,
    this.sourceType,
    this.citation,
    this.attestation,
  });

  const AttestedValue.empty()
      : value = null,
        sourceType = null,
        citation = null,
        attestation = null;

  final T? value;
  final SourceType? sourceType;

  /// Free-text citation: document, page/section, date (spec §0.3).
  final String? citation;
  final Attestation? attestation;

  bool get isComplete =>
      value != null &&
      sourceType != null &&
      (citation?.trim().isNotEmpty ?? false) &&
      attestation != null;

  Map<String, Object?> toJson(Object? Function(T value) encodeValue) => {
        'value': value == null ? null : encodeValue(value as T),
        'source_type': sourceType?.wire,
        'citation': citation,
        'attestation': attestation?.toJson(),
      };

  static AttestedValue<T> fromJson<T>(
    Map<String, Object?> json,
    T Function(Object? raw) decodeValue,
  ) =>
      AttestedValue<T>(
        value: json['value'] == null ? null : decodeValue(json['value']),
        sourceType: json['source_type'] == null
            ? null
            : SourceType.fromWire(json['source_type'] as String),
        citation: json['citation'] as String?,
        attestation: json['attestation'] == null
            ? null
            : Attestation.fromJson(
                (json['attestation'] as Map).cast<String, Object?>()),
      );

  @override
  bool operator ==(Object other) =>
      other is AttestedValue<T> &&
      other.value == value &&
      other.sourceType == sourceType &&
      other.citation == citation &&
      other.attestation == attestation;

  @override
  int get hashCode => Object.hash(value, sourceType, citation, attestation);
}

/// Bookkeeping fields every entity carries (spec §2: all entities get
/// `id`, `created_at`, `updated_at`, `created_by`). Held by composition.
@immutable
class EntityMeta {
  const EntityMeta({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  final Id id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Id createdBy;

  Map<String, Object?> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'created_by': createdBy,
      };

  factory EntityMeta.fromJson(Map<String, Object?> json) => EntityMeta(
        id: json['id'] as Id,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        createdBy: json['created_by'] as Id,
      );

  @override
  bool operator ==(Object other) =>
      other is EntityMeta &&
      other.id == id &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.createdBy == createdBy;

  @override
  int get hashCode => Object.hash(id, createdAt, updatedAt, createdBy);
}

/// Voltage system context for a rated voltage (spec §2.1 Project).
enum VoltageSystem {
  threePhaseDelta('3ph_delta'),
  threePhaseWye('3ph_wye'),
  singlePhase('1ph'),
  other('other');

  const VoltageSystem(this.wire);
  final String wire;

  static VoltageSystem fromWire(String wire) =>
      VoltageSystem.values.firstWhere((v) => v.wire == wire);
}

/// A voltage rating as entered by the user, with slash-rating context.
/// Slash-rating applicability rules are owner-configured registry parameters,
/// never core assumptions.
@immutable
class VoltageRating {
  const VoltageRating({required this.volts, required this.slashRating});

  final double volts;
  final bool slashRating;

  Map<String, Object?> toJson() =>
      {'volts': volts, 'slash_rating': slashRating};

  factory VoltageRating.fromJson(Map<String, Object?> json) => VoltageRating(
        volts: (json['volts'] as num).toDouble(),
        slashRating: json['slash_rating'] as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is VoltageRating &&
      other.volts == volts &&
      other.slashRating == slashRating;

  @override
  int get hashCode => Object.hash(volts, slashRating);
}
