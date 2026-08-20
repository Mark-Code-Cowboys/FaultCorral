// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Rules registry (spec §3.1): the owner's rules, in the owner's words, with
// the owner's sign-off. Status wire values ('unverified'/'verified'/
// 'disabled') are rendered from data; the app only records who signed off
// and when — it never asserts anything about the standard.

import 'dart:convert';

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

class RegistryScreen extends StatefulWidget {
  const RegistryScreen({super.key, required this.state});

  final AppState state;

  @override
  State<RegistryScreen> createState() => _RegistryScreenState();
}

class _RegistryScreenState extends State<RegistryScreen> {
  AppState get app => widget.state;

  Color _statusColor(RuleStatus status) => switch (status) {
        RuleStatus.verified => Colors.green,
        RuleStatus.unverified => Colors.red,
        RuleStatus.disabled => Colors.grey,
      };

  Future<void> _edit(RuleRegistryEntry entry) async {
    final updated = await showDialog<RuleRegistryEntry>(
      context: context,
      builder: (context) => _RuleDialog(state: app, entry: entry),
    );
    if (updated != null) {
      app.store
          .saveRegistryEntry(app.shop.meta.id, updated, by: app.user.meta.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = app.registry;
    return Scaffold(
      appBar: AppBar(title: const Text('Rules registry')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child:
                Text('Every rule ships awaiting your sign-off. Review each one '
                    'against your licensed copy of the standard, write the '
                    'description in your own words, fill the clause pointer, '
                    'then sign it off. The engine refuses to finalize any '
                    'project while a fired rule lacks sign-off.'),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final entry in registry.entries.values)
                  ListTile(
                    leading: Icon(Icons.circle,
                        size: 12, color: _statusColor(entry.status)),
                    title: Text('${entry.name}  ·  v${entry.version}'),
                    subtitle: Text(
                      [
                        'status: ${entry.status.wire}',
                        if (entry.clausePointer?.isNotEmpty ?? false)
                          'clause: ${entry.clausePointer}',
                        if (entry.verifiedBy != null)
                          'signed off by ${entry.verifiedBy} on '
                              '${entry.verifiedDate?.toIso8601String().substring(0, 10)}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _edit(entry),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.state, required this.entry});

  final AppState state;
  final RuleRegistryEntry entry;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _description =
      TextEditingController(text: widget.entry.description);
  late final _clause =
      TextEditingController(text: widget.entry.clausePointer ?? '');
  late final _params = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(widget.entry.params));
  String? _paramsError;

  Map<String, Object?>? _parseParams() {
    try {
      final parsed = jsonDecode(_params.text);
      return (parsed as Map).cast<String, Object?>();
    } catch (e) {
      setState(() => _paramsError = 'Invalid JSON: $e');
      return null;
    }
  }

  void _saveWith(RuleStatus status) {
    final params = _parseParams();
    if (params == null) return;
    final signOff = status == RuleStatus.verified;
    Navigator.of(context).pop(widget.entry.copyWith(
      description: _description.text.trim(),
      clausePointer: _clause.text.trim(),
      params: params,
      status: status,
      verifiedBy: signOff ? widget.state.user.meta.id : widget.entry.verifiedBy,
      verifiedDate:
          signOff ? DateTime.now().toUtc() : widget.entry.verifiedDate,
      version: widget.entry.version + 1,
    ));
  }

  Future<void> _confirmSignOff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign off this rule'),
        content: const Text(
            'By signing off, you record that YOU have checked this rule '
            '(description, clause pointer, and parameters) against your '
            'licensed copy of the standard, and that its wording is your '
            'own. The sign-off is stored with your user id and the date, '
            'and is stamped into every report this rule contributes to.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('I checked it — sign off')),
        ],
      ),
    );
    if (confirmed ?? false) _saveWith(RuleStatus.verified);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.entry.name} (${widget.entry.id})'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Description (your own words — never '
                        'standard text)'),
              ),
              TextField(
                controller: _clause,
                decoration: const InputDecoration(
                    labelText: 'Clause pointer (your citation, e.g. "SB4.x")'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _params,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Parameters (JSON)',
                  errorText: _paramsError,
                ),
                onChanged: (_) => setState(() => _paramsError = null),
              ),
              const SizedBox(height: 4),
              Text('Current status: ${widget.entry.status.wire}',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => _saveWith(RuleStatus.disabled),
            child: const Text('Disable')),
        TextButton(
            onPressed: () => _saveWith(RuleStatus.unverified),
            child: const Text('Save without sign-off')),
        FilledButton(
            onPressed: _confirmSignOff, child: const Text('Sign off…')),
      ],
    );
  }
}
