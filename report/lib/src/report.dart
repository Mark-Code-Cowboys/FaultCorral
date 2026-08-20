// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// SCCR determination worksheet PDF (spec §6). The report is the responsible
// person's document; the app is the pencil. Nowhere may the app's name
// appear as the source of any rating or determination (spec §6.4), and the
// corral metaphor never appears in report output (spec §5).

import 'dart:convert';
import 'dart:typed_data';

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Placeholder until the owner supplies final language. Ship-blocking.
const disclaimerPlaceholder = '[[LEGAL-DISCLAIMER - ATTORNEY TEXT REQUIRED]]';

/// Fixed attribution line (spec §6.4) — final product copy.
const attributionLine = 'Generated with FaultCorral - a documentation tool. '
    'All values user-supplied and attested.';

// TODO(owner-verify): owner-authored method statement template (spec §6.1.2).
const methodStatementPlaceholder =
    '[[METHOD STATEMENT - owner-authored template text required]]';

// TODO(owner-verify): attestation statement wording (owner + attorney).
const attestationStatementPlaceholder =
    '[[ATTESTATION STATEMENT - owner/attorney text required]]';

/// Everything the report renders. Values come from the snapshot and rollup
/// result; nothing is computed here beyond formatting.
class ReportInputs {
  const ReportInputs({
    required this.snapshot,
    required this.result,
    required this.registry,
    required this.flagAcknowledgments,
    required this.shopName,
    required this.responsibleName,
    required this.responsibleTitle,
    required this.generatedAt,
    required this.appVersion,
    this.userNames = const {},
    this.methodStatement,
    this.attestationStatement,
    this.disclaimerText,
    this.legalFooterAddendum,
    this.revisionHistory = const [],
  });

  final ProjectSnapshot snapshot;
  final RollupResult result;
  final RulesRegistry registry;
  final List<FlagAcknowledgment> flagAcknowledgments;
  final String shopName;
  final String responsibleName;
  final String responsibleTitle;
  final DateTime generatedAt;
  final String appVersion;

  /// userId → display name for attester columns.
  final Map<String, String> userNames;

  /// Owner-authored template text; placeholder until supplied.
  final String? methodStatement;
  final String? attestationStatement;

  /// Attorney text; placeholder until supplied (ship-blocking).
  final String? disclaimerText;

  /// Shop-supplied addendum; may add to the disclaimer block, never
  /// replace it (spec §6.4).
  final String? legalFooterAddendum;

  final List<String> revisionHistory;
}

/// Which watermarks the report must carry (spec §6.4, §0.5).
/// Pure and separately testable.
List<String> watermarksFor(ReportInputs inputs) => [
      if (inputs.snapshot.project.status != ProjectStatus.finalized) 'DRAFT',
      if (inputs.result.containsUnverifiedRuleResults)
        'CONTAINS UNVERIFIED RULES - NOT FOR USE',
    ];

/// The footer disclaimer block, in render order. Pure and testable.
List<String> footerLinesFor(ReportInputs inputs) => [
      inputs.disclaimerText ?? disclaimerPlaceholder,
      if (inputs.legalFooterAddendum != null) inputs.legalFooterAddendum!,
      attributionLine,
    ];

String _displayName(ReportInputs inputs, String? userId) =>
    userId == null ? '' : (inputs.userNames[userId] ?? userId);

String _formatDate(DateTime? dt) =>
    dt == null ? '' : dt.toUtc().toIso8601String().substring(0, 10);

String _formatKa(double? ka) =>
    ka == null ? 'NOT DETERMINED' : '${_trimNum(ka)} kA';

String _trimNum(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// circuitId → 'Feeder > Branch 2 > ...' path labels.
Map<String, String> circuitPaths(ProjectSnapshot snapshot) {
  final byId = {for (final c in snapshot.circuits) c.meta.id: c};
  String pathFor(Circuit c) {
    final labels = <String>[c.label];
    var parent = c.parentCircuitId;
    var hops = 0;
    while (parent != null && hops++ < 100) {
      final p = byId[parent];
      if (p == null) break;
      labels.insert(0, p.label);
      parent = p.parentCircuitId;
    }
    return labels.join(' > ');
  }

  return {for (final c in snapshot.circuits) c.meta.id: pathFor(c)};
}

/// Builds the report PDF. Deterministic for identical inputs (including
/// [ReportInputs.generatedAt]), so the bytes can be hashed into the
/// finalization record (spec §4).
class SccrReportBuilder {
  const SccrReportBuilder();

  Future<Uint8List> buildPdf(ReportInputs inputs) async {
    // No Info metadata on purpose: the pdf library stamps DateTime.now()
    // into any Info dict, which would break byte-for-byte determinism
    // (spec §4). Document identity lives in the rendered content instead.
    // PDF 1.4 keeps the trailer as plain text so _pinDocumentId can fix the
    // randomly generated /ID.
    final doc = pw.Document(version: PdfVersion.pdf_1_4);

    final watermarks = watermarksFor(inputs);
    final footerLines = footerLinesFor(inputs);
    final paths = circuitPaths(inputs.snapshot);
    final project = inputs.snapshot.project;

    final theme = pw.PageTheme(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 64),
      buildBackground: watermarks.isEmpty
          ? null
          : (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Transform.rotate(
                    angle: 0.6,
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        for (final mark in watermarks)
                          pw.Text(
                            mark,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: mark.length > 10 ? 28 : 96,
                              color: PdfColors.grey300,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
    );

    pw.Widget footer(pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Divider(thickness: 0.5),
            for (final line in footerLines)
              pw.Text(line,
                  style: const pw.TextStyle(
                      fontSize: 6, color: PdfColors.grey700)),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 7),
              ),
            ),
          ],
        );

    pw.Widget heading(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
          child: pw.Text(text,
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        );

    final panelSccrLines = [
      for (final rv in project.ratedVoltages)
        '${_formatKa(inputs.result.panelSccrKaByVoltage[rv.key])} at '
            '${_trimNum(rv.volts)} V ${rv.system.wire.replaceAll('_', ' ')}',
    ];

    doc.addPage(pw.MultiPage(
      pageTheme: theme,
      footer: footer,
      build: (context) => [
        // --- 1. Cover block (spec §6.1.1) --------------------------------
        pw.Text(inputs.shopName,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Short-Circuit Current Rating Determination Worksheet',
            style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerCount: 0,
          data: [
            ['Project', project.name],
            ['Customer', project.customer ?? ''],
            ['Panel / drawing no.', project.panelNumber ?? ''],
            ['Revision', project.revision ?? ''],
            [
              'Rated voltage(s)',
              project.ratedVoltages
                  .map((rv) =>
                      '${_trimNum(rv.volts)} V ${rv.system.wire.replaceAll('_', ' ')}')
                  .join('; '),
            ],
            ['Date', _formatDate(inputs.generatedAt)],
            [
              'Determined SCCR (as attested by ${inputs.responsibleName})',
              panelSccrLines.join('; '),
            ],
          ],
        ),

        // --- 2. Determination summary (spec §6.1.2) -----------------------
        heading('Determination summary'),
        pw.Text(inputs.methodStatement ?? methodStatementPlaceholder,
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
        pw.Text('Rules registry versions in force:',
            style: const pw.TextStyle(fontSize: 9)),
        pw.TableHelper.fromTextArray(
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle:
              pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          headers: ['Rule', 'Version', 'Status'],
          data: [
            for (final id
                in inputs.result.registryVersions.keys.toList()..sort())
              [
                id,
                inputs.result.registryVersions[id].toString(),
                inputs.registry[id]?.status.wire ?? '',
              ],
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text('Limiting component(s):',
            style: const pw.TextStyle(fontSize: 9)),
        if (inputs.result.limitingComponents.isEmpty)
          pw.Text('None determined.', style: const pw.TextStyle(fontSize: 9))
        else
          pw.TableHelper.fromTextArray(
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle:
                pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            headers: ['Rank', 'Tag', 'Effective SCCR'],
            data: [
              for (var i = 0; i < inputs.result.limitingComponents.length; i++)
                [
                  '${i + 1}',
                  inputs.result.limitingComponents[i].tag,
                  _formatKa(
                      inputs.result.limitingComponents[i].effectiveSccrKa),
                ],
            ],
          ),

        // --- 3. Component table (spec §6.1.3) -----------------------------
        heading('Components'),
        pw.TableHelper.fromTextArray(
          cellStyle: const pw.TextStyle(fontSize: 6.5),
          headerStyle:
              pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
          headers: [
            'Circuit path',
            'Tag',
            'Category',
            'Mfr',
            'Part no.',
            'Voltage',
            'SCCR',
            'Source',
            'Citation',
            'Attested by',
            'Date',
          ],
          data: [
            for (final c in inputs.snapshot.components)
              [
                paths[c.circuitId] ?? c.circuitId,
                c.tag,
                c.category == ComponentCategory.other
                    ? (c.categoryOtherLabel ?? 'other')
                    : c.category.wire.replaceAll('_', ' '),
                c.manufacturer ?? '',
                c.partNumber ?? '',
                c.voltageRating.value == null
                    ? ''
                    : '${_trimNum(c.voltageRating.value!.volts)} V'
                        '${c.voltageRating.value!.slashRating ? ' (slash)' : ''}',
                c.sccrKa.value == null ? 'UNRATED' : _formatKa(c.sccrKa.value),
                c.sccrKa.sourceType?.wire.replaceAll('_', ' ') ?? '',
                c.sccrKa.citation ?? '',
                _displayName(inputs, c.sccrKa.attestation?.userId),
                _formatDate(c.sccrKa.attestation?.timestamp),
              ],
          ],
        ),

        // --- 5. Flags & resolutions (spec §6.1.5) -------------------------
        heading('Flags and resolutions'),
        if (inputs.result.flags.isEmpty)
          pw.Text('No flags raised by the configured rules.',
              style: const pw.TextStyle(fontSize: 9))
        else
          pw.TableHelper.fromTextArray(
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerStyle:
                pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            headers: ['Severity', 'Rule', 'Message', 'Resolution'],
            data: [
              for (final flag in inputs.result.flags)
                [
                  flag.severity.wire.toUpperCase(),
                  '${flag.ruleId} v${flag.ruleVersion}',
                  flag.message,
                  _resolutionFor(inputs, flag),
                ],
            ],
          ),

        // --- 6. Explainability appendix (spec §6.1.6, §3.2) ---------------
        heading('Appendix: per-component value trace'),
        for (final trace in inputs.result.traces) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            '${trace.tag} - effective ${_formatKa(trace.effectiveSccrKa)}',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          for (final step in trace.steps)
            pw.Bullet(
              text: step.ruleId == null
                  ? step.description
                  : '${step.description} [rule: ${step.ruleId}]',
              style: const pw.TextStyle(fontSize: 7.5),
              bulletSize: 1.5,
            ),
        ],

        // --- 7. Attestation block (spec §6.1.7) ---------------------------
        heading('Attestation'),
        pw.Text(inputs.attestationStatement ?? attestationStatementPlaceholder,
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 20),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Printed name: ${inputs.responsibleName}',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Text('Title: ${inputs.responsibleTitle}',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Signature: _______________________',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Text('Date: _____________',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ]),

        // --- 8. Revision history (spec §6.1.8) ----------------------------
        heading('Revision history'),
        if (inputs.revisionHistory.isEmpty)
          pw.Text('No prior revisions recorded.',
              style: const pw.TextStyle(fontSize: 9))
        else
          for (final line in inputs.revisionHistory)
            pw.Bullet(
                text: line,
                style: const pw.TextStyle(fontSize: 8),
                bulletSize: 1.5),
      ],
    ));

    final bytes = await doc.save();
    return _pinDocumentId(bytes);
  }

  String _resolutionFor(ReportInputs inputs, EngineFlag flag) {
    if (flag.severity != FlagSeverity.warning) return '';
    final acks = inputs.flagAcknowledgments.where((a) => a.flagKey == flag.key);
    if (acks.isEmpty) return 'UNRESOLVED';
    final ack = acks.first;
    return 'Acknowledged by ${_displayName(inputs, ack.userId)} on '
        '${_formatDate(ack.timestamp)}: ${ack.note}';
  }

  /// The pdf library writes a random /ID into the trailer, which would make
  /// otherwise-identical documents hash differently. Replace it with an ID
  /// derived from the rest of the bytes so identical inputs produce
  /// identical files (spec §4: deterministic enough to hash).
  Uint8List _pinDocumentId(Uint8List bytes) {
    final text = latin1.decode(bytes);
    final match = RegExp(r'/ID\s*\[\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*\]')
        .firstMatch(text);
    if (match == null) return bytes;
    final idLength = match.group(1)!.length;
    final withoutId = text.replaceRange(match.start, match.end, '');
    var seed = 0x811c9dc5;
    for (final unit in withoutId.codeUnits) {
      seed ^= unit;
      seed = (seed * 0x01000193) & 0xFFFFFFFF;
    }
    final pinned = seed.toRadixString(16).padLeft(8, '0') * (idLength ~/ 8 + 1);
    final id = pinned.substring(0, idLength);
    return Uint8List.fromList(latin1.encode(
        text.replaceRange(match.start, match.end, '/ID [<$id> <$id>]')));
  }
}
