// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import '../model/circuit.dart';
import '../model/combo_rating.dart';
import '../model/component.dart';
import '../model/project.dart';

/// Everything the engine needs about one project, frozen (spec §3.2).
/// Same snapshot + same registry snapshot ⇒ identical rollup output.
@immutable
class ProjectSnapshot {
  ProjectSnapshot({
    required this.project,
    required Iterable<Circuit> circuits,
    required Iterable<Component> components,
    Iterable<ComboRating> comboRatings = const [],
  })  : circuits = List.unmodifiable(circuits),
        components = List.unmodifiable(components),
        comboRatings = List.unmodifiable(comboRatings);

  final Project project;
  final List<Circuit> circuits;
  final List<Component> components;
  final List<ComboRating> comboRatings;

  Map<String, Object?> toJson() => {
        'project': project.toJson(),
        'circuits': circuits.map((c) => c.toJson()).toList(),
        'components': components.map((c) => c.toJson()).toList(),
        'combo_ratings': comboRatings.map((c) => c.toJson()).toList(),
      };

  factory ProjectSnapshot.fromJson(Map<String, Object?> json) =>
      ProjectSnapshot(
        project:
            Project.fromJson((json['project'] as Map).cast<String, Object?>()),
        circuits: (json['circuits'] as List)
            .map((c) => Circuit.fromJson((c as Map).cast<String, Object?>())),
        components: (json['components'] as List)
            .map((c) => Component.fromJson((c as Map).cast<String, Object?>())),
        comboRatings: (json['combo_ratings'] as List? ?? []).map(
            (c) => ComboRating.fromJson((c as Map).cast<String, Object?>())),
      );
}
