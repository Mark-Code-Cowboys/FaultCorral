// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Shop library (spec §2.1): versioned, reusable catalog. Edits create a new
// version; projects keep the version they pinned. Deleting never mutates
// historical projects (soft delete via a new version).

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  AppState get app => widget.state;

  Future<void> _edit(LibraryItem? existing) async {
    final saved = await showDialog<LibraryItem>(
      context: context,
      builder: (context) => _LibraryItemDialog(state: app, existing: existing),
    );
    if (saved != null) {
      app.store.saveLibraryItem(saved, by: app.user.meta.id);
      setState(() {});
    }
  }

  void _softDelete(LibraryItem item) {
    app.store.saveLibraryItem(
      LibraryItem(
        meta: touch(item.meta),
        shopId: item.shopId,
        manufacturer: item.manufacturer,
        partNumber: item.partNumber,
        category: item.category,
        categoryOtherLabel: item.categoryOtherLabel,
        version: item.version + 1,
        defaultVoltageRating: item.defaultVoltageRating,
        defaultSccrKa: item.defaultSccrKa,
        defaultInterruptingRatingKa: item.defaultInterruptingRatingKa,
        defaultCurrentLimiting: item.defaultCurrentLimiting,
        deleted: true,
      ),
      by: app.user.meta.id,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = app.store.libraryForShop(app.shop.meta.id);
    return Scaffold(
      appBar: AppBar(title: const Text('Shop library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('New item'),
      ),
      body: items.isEmpty
          ? const Center(
              child: Text(
                  'Library is empty.\nTip: check "Save to library" while '
                  'entering components and it fills itself.',
                  textAlign: TextAlign.center),
            )
          : ListView(
              children: [
                for (final item in items)
                  ListTile(
                    title: Text('${item.manufacturer} ${item.partNumber}'),
                    subtitle: Text([
                      item.category.wire.replaceAll('_', ' '),
                      'v${item.version}',
                      if (item.defaultSccrKa.value != null)
                        'default ${item.defaultSccrKa.value} kA '
                            '(${item.defaultSccrKa.sourceType?.wire})',
                    ].join(' · ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            tooltip: 'Edit (creates a new version)',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _edit(item)),
                        IconButton(
                            tooltip: 'Remove from library (historical projects '
                                'keep their pinned versions)',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _softDelete(item)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _LibraryItemDialog extends StatefulWidget {
  const _LibraryItemDialog({required this.state, this.existing});

  final AppState state;
  final LibraryItem? existing;

  @override
  State<_LibraryItemDialog> createState() => _LibraryItemDialogState();
}

class _LibraryItemDialogState extends State<_LibraryItemDialog> {
  late final _manufacturer =
      TextEditingController(text: widget.existing?.manufacturer ?? '');
  late final _partNumber =
      TextEditingController(text: widget.existing?.partNumber ?? '');
  late final _volts = TextEditingController(
      text: widget.existing?.defaultVoltageRating.value?.volts
              .toStringAsFixed(0) ??
          '');
  late final _sccr = TextEditingController(
      text: widget.existing?.defaultSccrKa.value?.toString() ?? '');
  late final _citation = TextEditingController(
      text: widget.existing?.defaultSccrKa.citation ?? '');
  late ComponentCategory _category =
      widget.existing?.category ?? ComponentCategory.circuitBreakerMccb;
  late SourceType _source =
      widget.existing?.defaultSccrKa.sourceType ?? SourceType.datasheet;

  void _save() {
    if (_manufacturer.text.trim().isEmpty || _partNumber.text.trim().isEmpty) {
      return;
    }
    final app = widget.state;
    final now = DateTime.now().toUtc();
    final attestation = Attestation(userId: app.user.meta.id, timestamp: now);
    final volts = double.tryParse(_volts.text.trim());
    final sccr = double.tryParse(_sccr.text.trim());
    final citation = _citation.text.trim();

    Navigator.of(context).pop(LibraryItem(
      meta: widget.existing == null
          ? newMeta('lib', app.user.meta.id)
          : touch(widget.existing!.meta),
      shopId: app.shop.meta.id,
      manufacturer: _manufacturer.text.trim(),
      partNumber: _partNumber.text.trim(),
      category: _category,
      version: (widget.existing?.version ?? 0) + 1,
      defaultVoltageRating: volts == null
          ? const AttestedValue<VoltageRating>.empty()
          : AttestedValue(
              value: VoltageRating(volts: volts, slashRating: false),
              sourceType: _source,
              citation: citation.isEmpty ? null : citation,
              attestation: attestation,
            ),
      defaultSccrKa: sccr == null
          ? const AttestedValue<double>.empty()
          : AttestedValue(
              value: sccr,
              sourceType: _source,
              citation: citation.isEmpty ? null : citation,
              attestation: attestation,
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'New library item'
          : 'Edit → v${(widget.existing!.version) + 1}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _manufacturer,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Manufacturer *')),
            TextField(
                controller: _partNumber,
                decoration: const InputDecoration(labelText: 'Part number *')),
            DropdownButtonFormField<ComponentCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in ComponentCategory.values)
                  DropdownMenuItem(
                      value: c, child: Text(c.wire.replaceAll('_', ' '))),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _volts,
                      decoration: const InputDecoration(
                          labelText: 'Default voltage (V)'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _sccr,
                      decoration: const InputDecoration(
                          labelText: 'Default SCCR (kA)'))),
            ]),
            DropdownButtonFormField<SourceType>(
              initialValue: _source,
              decoration: const InputDecoration(labelText: 'Source'),
              items: [
                for (final s in SourceType.values)
                  DropdownMenuItem(
                      value: s, child: Text(s.wire.replaceAll('_', ' '))),
              ],
              onChanged: (v) => setState(() => _source = v ?? _source),
            ),
            TextField(
                controller: _citation,
                decoration: const InputDecoration(
                    labelText: 'Citation (document, page, date)')),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
