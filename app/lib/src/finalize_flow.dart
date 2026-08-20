// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Finalization flow (spec §2.1, §3.1) and report generation (spec §6).
// The engine gate is authoritative: blockers must be fixed, every fired
// rule needs owner sign-off, and every WARNING needs a recorded
// acknowledgment with a note before the snapshot freezes.

import 'package:crypto/crypto.dart' show sha256;
import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:faultcorral_report/faultcorral_report.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

Future<void> showFinalizeFlow(
  BuildContext context, {
  required AppState state,
  required String projectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _FinalizeDialog(state: state, projectId: projectId),
  );
}

class _FinalizeDialog extends StatefulWidget {
  const _FinalizeDialog({required this.state, required this.projectId});

  final AppState state;
  final String projectId;

  @override
  State<_FinalizeDialog> createState() => _FinalizeDialogState();
}

class _FinalizeDialogState extends State<_FinalizeDialog> {
  late RollupResult _result;
  late Map<String, FlagAcknowledgment> _acks;

  AppState get app => widget.state;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _result = const RollupEngine()
        .evaluate(app.store.loadSnapshot(widget.projectId), app.registry);
    _acks = {
      for (final ack in app.store.flagAcksForProject(widget.projectId))
        ack.flagKey: ack,
    };
  }

  List<EngineFlag> get _blockers =>
      _result.flags.where((f) => f.severity == FlagSeverity.blocker).toList();
  List<EngineFlag> get _warnings =>
      _result.flags.where((f) => f.severity == FlagSeverity.warning).toList();

  bool get _ready =>
      _blockers.isEmpty &&
      !_result.containsUnverifiedRuleResults &&
      _warnings.every((f) => _acks.containsKey(f.key));

  Future<void> _acknowledge(EngineFlag flag) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Acknowledge warning'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(flag.message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Your note (required — printed in the report)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Record acknowledgment')),
          ],
        );
      },
    );
    if (note == null || note.trim().isEmpty) return;
    app.store.saveFlagAcknowledgment(
      FlagAcknowledgment(
        flagKey: flag.key,
        projectId: widget.projectId,
        userId: app.user.meta.id,
        timestamp: DateTime.now().toUtc(),
        note: note.trim(),
      ),
      by: app.user.meta.id,
    );
    setState(_reload);
  }

  Future<void> _finalize() async {
    try {
      final frozen = app.store.finalizeProject(
        projectId: widget.projectId,
        by: app.user.meta.id,
        acceptedAcknowledgmentTextVersion: _acceptedTextVersion() ?? 'unknown',
        appVersion: appVersion,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await generateReport(
        // ignore: use_build_context_synchronously
        context,
        state: app,
        projectId: widget.projectId,
        draft: false,
        finalizedSnapshotRef: frozen.sha256Hex,
      );
    } on FinalizationBlocked catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
      setState(_reload);
    }
  }

  String? _acceptedTextVersion() {
    final records = app.store.acknowledgmentsForUser(app.user.meta.id);
    return records.isEmpty ? null : records.last.textVersion;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Finalize project'),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('Finalizing freezes an immutable snapshot (data + rules '
                'registry versions) and hashes it. Post-finalization changes '
                'require a new revision.'),
            const SizedBox(height: 12),
            if (_result.containsUnverifiedRuleResults)
              const ListTile(
                leading: Icon(Icons.gpp_maybe, color: Colors.red),
                title: Text('Unverified rules fired'),
                subtitle:
                    Text('Open the rules registry and sign off every rule you '
                        'have checked against your copy of the standard.'),
              ),
            if (_blockers.isNotEmpty) ...[
              Text('Blockers — fix before finalizing (${_blockers.length})',
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
              for (final flag in _blockers)
                ListTile(
                    dense: true,
                    leading: const Icon(Icons.block, size: 16),
                    title: Text(flag.message,
                        style: const TextStyle(fontSize: 12))),
            ],
            if (_warnings.isNotEmpty) ...[
              Text('Warnings — acknowledge with a note (${_warnings.length})',
                  style: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold)),
              for (final flag in _warnings)
                ListTile(
                  dense: true,
                  leading: Icon(
                      _acks.containsKey(flag.key)
                          ? Icons.check_circle
                          : Icons.pending_outlined,
                      size: 16),
                  title:
                      Text(flag.message, style: const TextStyle(fontSize: 12)),
                  subtitle: _acks.containsKey(flag.key)
                      ? Text('Acknowledged: ${_acks[flag.key]!.note}',
                          style: const TextStyle(fontSize: 11))
                      : null,
                  trailing: _acks.containsKey(flag.key)
                      ? null
                      : TextButton(
                          onPressed: () => _acknowledge(flag),
                          child: const Text('Acknowledge…')),
                ),
            ],
            if (_ready)
              const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Ready to finalize'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _ready ? _finalize : null,
          child: const Text('Finalize and generate report'),
        ),
      ],
    );
  }
}

/// Builds the §6 report PDF and saves it where the user chooses. Draft
/// reports carry watermarks automatically (non-finalized project and/or
/// unverified-rule results). On finalized reports, the PDF hash is recorded
/// in a ReportRecord tied to the frozen snapshot.
Future<void> generateReport(
  BuildContext context, {
  required AppState state,
  required String projectId,
  required bool draft,
  String? finalizedSnapshotRef,
}) async {
  final names = await showDialog<(String, String)>(
    context: context,
    builder: (context) {
      final name = TextEditingController(text: state.user.displayName);
      final title = TextEditingController();
      return AlertDialog(
        title: const Text('Report attestation block'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'Responsible person (printed name)')),
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop((name.text, title.text)),
              child: const Text('Continue')),
        ],
      );
    },
  );
  if (names == null) return;

  final snapshot = state.store.loadSnapshot(projectId);
  final registry = state.registry;
  final result = const RollupEngine().evaluate(snapshot, registry);
  final generatedAt = DateTime.now().toUtc();

  final bytes = await const SccrReportBuilder().buildPdf(ReportInputs(
    snapshot: snapshot,
    result: result,
    registry: registry,
    flagAcknowledgments: state.store.flagAcksForProject(projectId),
    shopName: state.shop.name,
    responsibleName: names.$1,
    responsibleTitle: names.$2,
    generatedAt: generatedAt,
    appVersion: appVersion,
    userNames: {state.user.meta.id: state.user.displayName},
    revisionHistory: [
      'Rev ${snapshot.project.revision ?? '-'} — generated '
          '${generatedAt.toIso8601String().substring(0, 10)}',
    ],
  ));

  final location = await getSaveLocation(
    suggestedName:
        '${snapshot.project.name.replaceAll(' ', '_')}_SCCR_worksheet.pdf',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ],
  );
  if (location == null) return;
  await XFile.fromData(bytes, mimeType: 'application/pdf')
      .saveTo(location.path);

  final pdfHash = sha256.convert(bytes).toString();
  if (!draft && finalizedSnapshotRef != null) {
    final records = state.store.acknowledgmentsForUser(state.user.meta.id);
    state.store.saveReportRecord(
      ReportRecord(
        meta: newMeta('rpt', state.user.meta.id),
        projectId: projectId,
        projectSnapshotRef: finalizedSnapshotRef,
        pdfSha256: pdfHash,
        registryVersions: result.registryVersions,
        acknowledgmentTextVersion:
            records.isEmpty ? 'unknown' : records.last.textVersion,
        appVersion: appVersion,
        draftWatermark: watermarksFor(ReportInputs(
          snapshot: snapshot,
          result: result,
          registry: registry,
          flagAcknowledgments: const [],
          shopName: state.shop.name,
          responsibleName: names.$1,
          responsibleTitle: names.$2,
          generatedAt: generatedAt,
          appVersion: appVersion,
        )).isNotEmpty,
      ),
      by: state.user.meta.id,
    );
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Report saved to ${location.path}\n'
        'SHA-256: ${pdfHash.substring(0, 16)}…'),
  ));
}
