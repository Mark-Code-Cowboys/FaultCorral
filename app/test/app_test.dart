// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Widget tests against an in-memory store. Placeholder values only.

import 'package:faultcorral_app/main.dart';
import 'package:faultcorral_app/src/acknowledgment_screen.dart';
import 'package:faultcorral_app/src/app_state.dart';
import 'package:faultcorral_app/src/project_screen.dart';
import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:faultcorral_store/faultcorral_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppState freshState() =>
    bootstrapState(FaultCorralStore(FaultCorralDatabase.memory()));

void main() {
  group('First-run acknowledgment (spec §0.4)', () {
    testWidgets('both boxes required; nothing pre-checked', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      AcknowledgmentRecord? accepted;
      await tester.pumpWidget(MaterialApp(
        home: AcknowledgmentScreen(
          gate: const AcknowledgmentGate(
              currentTextVersion: acknowledgmentTextVersion),
          onAccepted: (r) => accepted = r,
        ),
      ));

      final checkboxes = find.byType(CheckboxListTile);
      expect(checkboxes, findsNWidgets(2));
      for (final box in tester.widgetList<CheckboxListTile>(checkboxes)) {
        expect(box.value, isFalse, reason: 'never pre-checked');
      }

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      await tester.tap(checkboxes.first);
      await tester.pump();
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull,
          reason: 'one box is not enough');

      await tester.tap(checkboxes.last);
      await tester.pump();
      await tester.tap(continueButton);
      expect(accepted, isNotNull);
      expect(accepted!.textVersion, acknowledgmentTextVersion);
    });

    testWidgets('app gates on acknowledgment and persists it', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = freshState();
      await tester.pumpWidget(FaultCorralApp(state: state));
      expect(find.byType(AcknowledgmentScreen), findsOneWidget);

      for (final box in find
          .byType(CheckboxListTile)
          .evaluate()
          .map((e) => e.widget)
          .cast<CheckboxListTile>()) {
        expect(box.value, isFalse);
      }
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(AcknowledgmentScreen), findsNothing);
      expect(
          state.store
              .needsAcknowledgment('user-local', acknowledgmentTextVersion),
          isFalse);
    });
  });

  group('Project workspace', () {
    testWidgets('UNRATED component appears in the resolve queue',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = freshState();
      final now = DateTime.utc(2026, 1, 1);
      final project = Project(
        meta: EntityMeta(
            id: 'proj-1', createdAt: now, updatedAt: now, createdBy: 'u'),
        shopId: state.shop.meta.id,
        name: 'Panel A',
        status: ProjectStatus.draft,
        ratedVoltages: const [
          RatedVoltage(
              volts: 480,
              system: VoltageSystem.threePhaseWye,
              slashRatingContext: false),
        ],
      );
      state.store.saveProject(project, by: 'u');
      state.store.saveCircuit(
        Circuit(
            meta: EntityMeta(
                id: 'circ-1', createdAt: now, updatedAt: now, createdBy: 'u'),
            projectId: 'proj-1',
            kind: CircuitKind.feeder,
            label: 'Incoming feeder'),
        by: 'u',
      );
      state.store.saveComponent(
        Component(
          meta: EntityMeta(
              id: 'comp-1', createdAt: now, updatedAt: now, createdBy: 'u'),
          circuitId: 'circ-1',
          category: ComponentCategory.circuitBreakerMccb,
          tag: 'CB1',
          powerCircuit: true,
        ),
        projectId: 'proj-1',
        by: 'u',
      );

      await tester.pumpWidget(MaterialApp(
        home: ProjectScreen(state: state, projectId: 'proj-1'),
      ));
      await tester.pump();

      expect(find.textContaining('UNRATED', findRichText: true), findsWidgets);
      // Two blockers: UNRATED SCCR and missing voltage rating.
      expect(find.textContaining('Blockers (2)'), findsOneWidget);
      // Panel value unresolved.
      expect(find.textContaining('unresolved'), findsOneWidget);
    });
  });
}
