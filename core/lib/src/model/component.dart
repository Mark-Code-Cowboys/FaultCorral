// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

/// Component categories (spec §2.1). Extensible: `other` carries an
/// owner-defined label on the component itself.
enum ComponentCategory {
  disconnectSwitch('disconnect_switch'),
  fusibleDisconnect('fusible_disconnect'),
  fuseAndHolder('fuse_and_holder'),
  circuitBreakerMccb('circuit_breaker_mccb'),
  motorCircuitProtector('motor_circuit_protector'),
  supplementaryProtector('supplementary_protector'),
  contactor('contactor'),
  motorStarterCombo('motor_starter_combo'),
  overloadRelay('overload_relay'),
  softStarter('soft_starter'),
  vfdDrive('vfd_drive'),
  powerDistributionBlock('power_distribution_block'),
  terminalBlock('terminal_block'),
  busbar('busbar'),
  powerTransformer('power_transformer'),
  controlTransformer('control_transformer'),
  spd('spd'),
  receptacle('receptacle'),
  switchOther('switch_other'),
  meterMonitor('meter_monitor'),
  other('other');

  const ComponentCategory(this.wire);
  final String wire;

  static ComponentCategory fromWire(String wire) =>
      ComponentCategory.values.firstWhere((v) => v.wire == wire);
}

/// Let-through data slot for current-limiting devices (spec §2.1).
/// STRUCTURE ONLY in early phases: any rating-elevation logic using this
/// data ships `disabled` in the registry until the owner writes and marks
/// the rule against his copy of the standard (spec §3.1 rule 7).
@immutable
class LetThroughData {
  const LetThroughData({
    this.peakLetThroughKa,
    this.i2t,
    this.citation,
    this.attestation,
  });

  final double? peakLetThroughKa;
  final double? i2t;
  final String? citation;
  final Attestation? attestation;

  Map<String, Object?> toJson() => {
        'peak_let_through_ka': peakLetThroughKa,
        'i2t': i2t,
        'citation': citation,
        'attestation': attestation?.toJson(),
      };

  factory LetThroughData.fromJson(Map<String, Object?> json) => LetThroughData(
        peakLetThroughKa: (json['peak_let_through_ka'] as num?)?.toDouble(),
        i2t: (json['i2t'] as num?)?.toDouble(),
        citation: json['citation'] as String?,
        attestation: json['attestation'] == null
            ? null
            : Attestation.fromJson(
                (json['attestation'] as Map).cast<String, Object?>()),
      );
}

/// A component instance placed on a circuit (spec §2.1).
///
/// SCCR and interrupting rating are DISTINCT fields and are never substituted
/// for one another anywhere in the system (spec §2.2 invariant).
@immutable
class Component {
  const Component({
    required this.meta,
    required this.circuitId,
    required this.category,
    required this.tag,
    required this.powerCircuit,
    this.categoryOtherLabel,
    this.libraryItemId,
    this.libraryItemVersion,
    this.quantity = 1,
    this.manufacturer,
    this.partNumber,
    this.voltageRating = const AttestedValue<VoltageRating>.empty(),
    this.sccrKa = const AttestedValue<double>.empty(),
    this.interruptingRatingKa = const AttestedValue<double>.empty(),
    this.currentLimiting,
    this.letThrough,
    this.comboRatingIds = const [],
    this.notes,
  });

  final EntityMeta meta;
  final Id circuitId;

  /// Null for one-off manual entries. When set, [libraryItemVersion] pins the
  /// library item version used, so later library edits never mutate
  /// historical projects (spec §2.2 invariant).
  final Id? libraryItemId;
  final int? libraryItemVersion;

  final int quantity;

  /// Position / device tag on the drawing.
  final String tag;

  final ComponentCategory category;

  /// Owner-defined label when [category] is [ComponentCategory.other].
  final String? categoryOtherLabel;

  final String? manufacturer;
  final String? partNumber;

  /// Control-circuit components can be recorded for completeness; whether
  /// they join the rollup is decided by the owner-configured scope rule,
  /// not hardcoded here (spec §2.1).
  final bool powerCircuit;

  final AttestedValue<VoltageRating> voltageRating;

  /// Short-circuit current rating in kA, user-supplied and attested.
  final AttestedValue<double> sccrKa;

  /// Interrupting rating in kA where applicable. Distinct from SCCR.
  final AttestedValue<double> interruptingRatingKa;

  /// User-declared current-limiting flag. Display only in early phases.
  final bool? currentLimiting;

  /// Structure-only slot; see [LetThroughData].
  final LetThroughData? letThrough;

  /// Series combinations the user has applied to this component.
  final List<Id> comboRatingIds;

  final String? notes;

  /// UNRATED: no complete, attested SCCR entry. Displayed loudly and blocks
  /// report finalization until deliberately resolved (spec §0.3).
  bool get isUnrated => !sccrKa.isComplete;

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'circuit_id': circuitId,
        'library_item_id': libraryItemId,
        'library_item_version': libraryItemVersion,
        'quantity': quantity,
        'tag': tag,
        'category': category.wire,
        'category_other_label': categoryOtherLabel,
        'manufacturer': manufacturer,
        'part_number': partNumber,
        'power_circuit': powerCircuit,
        'voltage_rating': voltageRating.toJson((v) => v.toJson()),
        'sccr_ka': sccrKa.toJson((v) => v),
        'interrupting_rating_ka': interruptingRatingKa.toJson((v) => v),
        'current_limiting': currentLimiting,
        'let_through': letThrough?.toJson(),
        'combo_rating_ids': comboRatingIds,
        'notes': notes,
      };

  factory Component.fromJson(Map<String, Object?> json) => Component(
        meta: EntityMeta.fromJson(json),
        circuitId: json['circuit_id'] as Id,
        libraryItemId: json['library_item_id'] as Id?,
        libraryItemVersion: json['library_item_version'] as int?,
        quantity: json['quantity'] as int,
        tag: json['tag'] as String,
        category: ComponentCategory.fromWire(json['category'] as String),
        categoryOtherLabel: json['category_other_label'] as String?,
        manufacturer: json['manufacturer'] as String?,
        partNumber: json['part_number'] as String?,
        powerCircuit: json['power_circuit'] as bool,
        voltageRating: AttestedValue.fromJson(
          (json['voltage_rating'] as Map).cast<String, Object?>(),
          (raw) => VoltageRating.fromJson((raw as Map).cast<String, Object?>()),
        ),
        sccrKa: AttestedValue.fromJson(
          (json['sccr_ka'] as Map).cast<String, Object?>(),
          (raw) => (raw as num).toDouble(),
        ),
        interruptingRatingKa: AttestedValue.fromJson(
          (json['interrupting_rating_ka'] as Map).cast<String, Object?>(),
          (raw) => (raw as num).toDouble(),
        ),
        currentLimiting: json['current_limiting'] as bool?,
        letThrough: json['let_through'] == null
            ? null
            : LetThroughData.fromJson(
                (json['let_through'] as Map).cast<String, Object?>()),
        comboRatingIds: (json['combo_rating_ids'] as List).cast<Id>().toList(),
        notes: json['notes'] as String?,
      );
}
