// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// "Your configured assumed ratings" (spec §3.1 slot 3): the table ships
// empty and is populated by the shop from its own review of the standard.
// The UI never presents these as anything but the shop's own values.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

class DefaultsScreen extends StatefulWidget {
  const DefaultsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<DefaultsScreen> createState() => _DefaultsScreenState();
}

class _DefaultsScreenState extends State<DefaultsScreen> {
  AppState get app => widget.state;

  late List<({ComponentCategory category, double sccrKa})> _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final rule = app.registry[RuleIds.assumedDefault]!;
    final table = (rule.params['defaults_table'] as List? ?? const []);
    _rows = [
      for (final raw in table.whereType<Map<Object?, Object?>>())
        (
          category: ComponentCategory.fromWire(raw['category'] as String),
          sccrKa: (raw['sccr_ka'] as num).toDouble(),
        ),
    ];
  }

  void _save() {
    final rule = app.registry[RuleIds.assumedDefault]!;
    app.store.saveRegistryEntry(
      app.shop.meta.id,
      rule.copyWith(
        params: {
          ...rule.params,
          'defaults_table': [
            for (final row in _rows)
              {'category': row.category.wire, 'sccr_ka': row.sccrKa},
          ],
        },
        version: rule.version + 1,
      ),
      by: app.user.meta.id,
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved. Registry entry version bumped — existing '
            'projects re-evaluate against the new table.')));
    setState(() {});
  }

  Future<void> _addRow() async {
    final row = await showDialog<({ComponentCategory category, double sccrKa})>(
      context: context,
      builder: (context) {
        var category = ComponentCategory.circuitBreakerMccb;
        final ka = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add assumed rating (your value)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ComponentCategory>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in ComponentCategory.values)
                      DropdownMenuItem(
                          value: c, child: Text(c.wire.replaceAll('_', ' '))),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => category = v ?? category),
                ),
                TextField(
                  controller: ka,
                  autofocus: true,
                  decoration:
                      const InputDecoration(labelText: 'Assumed SCCR (kA)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(ka.text.trim());
                  if (value != null) {
                    Navigator.of(context)
                        .pop((category: category, sccrKa: value));
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
    if (row != null) {
      setState(() {
        _rows.removeWhere((r) => r.category == row.category);
        _rows.add(row);
      });
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your configured assumed ratings')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRow,
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
                'These are your shop\'s own configured values for components '
                'entered with source "assumed_default". The table ships '
                'empty; populate it from your review of your licensed copy '
                'of the standard. FaultCorral only cross-checks entries '
                'against this table — it does not supply values.'),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('No entries configured yet.'))
                : ListView(
                    children: [
                      for (final row in _rows)
                        ListTile(
                          title: Text(row.category.wire.replaceAll('_', ' ')),
                          subtitle: Text('${row.sccrKa} kA'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              setState(() => _rows.remove(row));
                              _save();
                            },
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
