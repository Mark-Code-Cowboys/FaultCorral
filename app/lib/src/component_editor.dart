// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Keyboard-first component entry (spec §5): type-ahead against the shop
// library, Tab through fields, Enter commits and clears for the next row
// without touching the mouse. Attestation is captured on commit (spec §0.3):
// SCCR requires value + source + citation or the component stays UNRATED.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

/// Persistent entry form at the bottom of the component pane.
class ComponentEntryForm extends StatefulWidget {
  const ComponentEntryForm({
    super.key,
    required this.state,
    required this.circuitId,
    required this.onCommit,
  });

  final AppState state;
  final String circuitId;
  final void Function(Component component) onCommit;

  @override
  State<ComponentEntryForm> createState() => ComponentEntryFormState();
}

class ComponentEntryFormState extends State<ComponentEntryForm> {
  final _tag = TextEditingController();
  final _manufacturer = TextEditingController();
  final _partNumber = TextEditingController();
  final _volts = TextEditingController();
  final _sccr = TextEditingController();
  final _citation = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _tagFocus = FocusNode();

  ComponentCategory _category = ComponentCategory.circuitBreakerMccb;
  SourceType _source = SourceType.datasheet;
  bool _slashRating = false;
  bool _powerCircuit = true;
  bool _saveToLibrary = false;
  LibraryItem? _pickedLibraryItem;

  @override
  void dispose() {
    for (final c in [
      _tag,
      _manufacturer,
      _partNumber,
      _volts,
      _sccr,
      _citation,
      _quantity
    ]) {
      c.dispose();
    }
    _tagFocus.dispose();
    super.dispose();
  }

  void _applyLibraryItem(LibraryItem item) {
    setState(() {
      _pickedLibraryItem = item;
      _manufacturer.text = item.manufacturer;
      _partNumber.text = item.partNumber;
      _category = item.category;
      final v = item.defaultVoltageRating;
      if (v.value != null) {
        _volts.text = v.value!.volts.toStringAsFixed(0);
        _slashRating = v.value!.slashRating;
      }
      final sccr = item.defaultSccrKa;
      if (sccr.value != null) {
        _sccr.text = sccr.value!.toString();
        _source = sccr.sourceType ?? _source;
        _citation.text = sccr.citation ?? '';
      }
    });
  }

  void _commit() {
    if (_tag.text.trim().isEmpty) {
      _tagFocus.requestFocus();
      return;
    }
    final app = widget.state;
    final now = DateTime.now().toUtc();
    final attestation = Attestation(userId: app.user.meta.id, timestamp: now);
    final volts = double.tryParse(_volts.text.trim());
    final sccr = double.tryParse(_sccr.text.trim());
    final citation = _citation.text.trim();

    AttestedValue<VoltageRating> voltageRating() => volts == null
        ? const AttestedValue<VoltageRating>.empty()
        : AttestedValue(
            value: VoltageRating(volts: volts, slashRating: _slashRating),
            sourceType: _source,
            citation: citation.isEmpty ? null : citation,
            attestation: attestation,
          );

    AttestedValue<double> sccrValue() => sccr == null
        ? const AttestedValue<double>.empty()
        : AttestedValue(
            value: sccr,
            sourceType: _source,
            citation: citation.isEmpty ? null : citation,
            attestation: attestation,
          );

    var libraryItemId = _pickedLibraryItem?.meta.id;
    var libraryItemVersion = _pickedLibraryItem?.version;

    if (_saveToLibrary && _partNumber.text.trim().isNotEmpty) {
      final latest = widget.state.store
          .libraryForShop(app.shop.meta.id)
          .where((item) =>
              item.partNumber == _partNumber.text.trim() &&
              item.manufacturer == _manufacturer.text.trim())
          .toList();
      final item = LibraryItem(
        meta: latest.isEmpty
            ? newMeta('lib', app.user.meta.id)
            : touch(latest.first.meta),
        shopId: app.shop.meta.id,
        manufacturer: _manufacturer.text.trim(),
        partNumber: _partNumber.text.trim(),
        category: _category,
        version: latest.isEmpty ? 1 : latest.first.version + 1,
        defaultVoltageRating: voltageRating(),
        defaultSccrKa: sccrValue(),
      );
      app.store.saveLibraryItem(item, by: app.user.meta.id);
      libraryItemId = item.meta.id;
      libraryItemVersion = item.version;
    }

    widget.onCommit(Component(
      meta: newMeta('comp', app.user.meta.id),
      circuitId: widget.circuitId,
      libraryItemId: libraryItemId,
      libraryItemVersion: libraryItemVersion,
      quantity: int.tryParse(_quantity.text.trim()) ?? 1,
      tag: _tag.text.trim(),
      category: _category,
      manufacturer:
          _manufacturer.text.trim().isEmpty ? null : _manufacturer.text.trim(),
      partNumber:
          _partNumber.text.trim().isEmpty ? null : _partNumber.text.trim(),
      powerCircuit: _powerCircuit,
      voltageRating: voltageRating(),
      sccrKa: sccrValue(),
    ));

    // Clear for rapid entry; keep category/source/citation as sticky
    // defaults for runs of similar components.
    setState(() {
      _tag.clear();
      _quantity.text = '1';
      _pickedLibraryItem = null;
    });
    _tagFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final library =
        widget.state.store.libraryForShop(widget.state.shop.meta.id);
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add component (Enter saves, keeps focus for the next one)',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _tag,
                  focusNode: _tagFocus,
                  autofocus: true,
                  decoration:
                      const InputDecoration(labelText: 'Tag *', isDense: true),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<ComponentCategory>(
                  initialValue: _category,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                      labelText: 'Category', isDense: true),
                  items: [
                    for (final c in ComponentCategory.values)
                      DropdownMenuItem(
                          value: c,
                          child: Text(c.wire.replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 200,
                child: RawAutocomplete<LibraryItem>(
                  textEditingController: _partNumber,
                  focusNode: FocusNode(),
                  optionsBuilder: (value) => value.text.isEmpty
                      ? const Iterable<LibraryItem>.empty()
                      : library.where((item) =>
                          item.partNumber
                              .toLowerCase()
                              .contains(value.text.toLowerCase()) ||
                          item.manufacturer
                              .toLowerCase()
                              .contains(value.text.toLowerCase())),
                  displayStringForOption: (item) => item.partNumber,
                  onSelected: _applyLibraryItem,
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmit) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                        labelText: 'Part number (type-ahead)', isDense: true),
                  ),
                  optionsViewBuilder: (context, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: SizedBox(
                        width: 320,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final item in options)
                              ListTile(
                                dense: true,
                                title: Text(
                                    '${item.manufacturer} ${item.partNumber}'),
                                subtitle: Text('library v${item.version}'
                                    '${item.defaultSccrKa.value != null ? ' · ${item.defaultSccrKa.value} kA default' : ''}'),
                                onTap: () => onSelected(item),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _manufacturer,
                  decoration: const InputDecoration(
                      labelText: 'Manufacturer', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _quantity,
                  decoration:
                      const InputDecoration(labelText: 'Qty', isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _volts,
                  decoration: const InputDecoration(
                      labelText: 'Voltage (V)', isDense: true),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _sccr,
                  decoration: const InputDecoration(
                      labelText: 'SCCR (kA)', isDense: true),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<SourceType>(
                  initialValue: _source,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                      labelText: 'SCCR source', isDense: true),
                  items: [
                    for (final s in SourceType.values)
                      DropdownMenuItem(
                          value: s,
                          child: Text(s.wire.replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _source = v ?? _source),
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _citation,
                  decoration: const InputDecoration(
                      labelText: 'Citation (document, page, date) *',
                      isDense: true),
                  onSubmitted: (_) => _commit(),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _miniCheckbox('Slash-rated', _slashRating,
                      (v) => setState(() => _slashRating = v)),
                  _miniCheckbox('Power circuit', _powerCircuit,
                      (v) => setState(() => _powerCircuit = v)),
                  _miniCheckbox('Save to library', _saveToLibrary,
                      (v) => setState(() => _saveToLibrary = v)),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add (Enter)'),
                    onPressed: _commit,
                  ),
                ]),
          ],
        ),
      ),
    );
  }

  Widget _miniCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 8),
    ]);
  }
}

/// Full editor dialog for an existing component.
Future<Component?> showComponentEditorDialog(
  BuildContext context, {
  required AppState state,
  required String circuitId,
  required Component existing,
}) {
  return showDialog<Component>(
    context: context,
    builder: (context) =>
        _EditComponentDialog(state: state, existing: existing),
  );
}

class _EditComponentDialog extends StatefulWidget {
  const _EditComponentDialog({required this.state, required this.existing});

  final AppState state;
  final Component existing;

  @override
  State<_EditComponentDialog> createState() => _EditComponentDialogState();
}

class _EditComponentDialogState extends State<_EditComponentDialog> {
  late final _tag = TextEditingController(text: widget.existing.tag);
  late final _manufacturer =
      TextEditingController(text: widget.existing.manufacturer ?? '');
  late final _partNumber =
      TextEditingController(text: widget.existing.partNumber ?? '');
  late final _volts = TextEditingController(
      text:
          widget.existing.voltageRating.value?.volts.toStringAsFixed(0) ?? '');
  late final _sccr = TextEditingController(
      text: widget.existing.sccrKa.value?.toString() ?? '');
  late final _citation =
      TextEditingController(text: widget.existing.sccrKa.citation ?? '');
  late final _interrupting = TextEditingController(
      text: widget.existing.interruptingRatingKa.value?.toString() ?? '');
  late final _interruptingCitation = TextEditingController(
      text: widget.existing.interruptingRatingKa.citation ?? '');
  late final _quantity =
      TextEditingController(text: widget.existing.quantity.toString());

  late ComponentCategory _category = widget.existing.category;
  late SourceType _source =
      widget.existing.sccrKa.sourceType ?? SourceType.datasheet;
  late SourceType _interruptingSource =
      widget.existing.interruptingRatingKa.sourceType ?? SourceType.datasheet;
  late bool _slashRating =
      widget.existing.voltageRating.value?.slashRating ?? false;
  late bool _powerCircuit = widget.existing.powerCircuit;

  void _save() {
    final now = DateTime.now().toUtc();
    final attestation =
        Attestation(userId: widget.state.user.meta.id, timestamp: now);
    final volts = double.tryParse(_volts.text.trim());
    final sccr = double.tryParse(_sccr.text.trim());
    final interrupting = double.tryParse(_interrupting.text.trim());
    final citation = _citation.text.trim();

    Navigator.of(context).pop(Component(
      meta: touch(widget.existing.meta),
      circuitId: widget.existing.circuitId,
      libraryItemId: widget.existing.libraryItemId,
      libraryItemVersion: widget.existing.libraryItemVersion,
      quantity: int.tryParse(_quantity.text.trim()) ?? 1,
      tag: _tag.text.trim(),
      category: _category,
      categoryOtherLabel: widget.existing.categoryOtherLabel,
      manufacturer:
          _manufacturer.text.trim().isEmpty ? null : _manufacturer.text.trim(),
      partNumber:
          _partNumber.text.trim().isEmpty ? null : _partNumber.text.trim(),
      powerCircuit: _powerCircuit,
      voltageRating: volts == null
          ? const AttestedValue<VoltageRating>.empty()
          : AttestedValue(
              value: VoltageRating(volts: volts, slashRating: _slashRating),
              sourceType: _source,
              citation: citation.isEmpty ? null : citation,
              attestation: attestation,
            ),
      sccrKa: sccr == null
          ? const AttestedValue<double>.empty()
          : AttestedValue(
              value: sccr,
              sourceType: _source,
              citation: citation.isEmpty ? null : citation,
              attestation: attestation,
            ),
      interruptingRatingKa: interrupting == null
          ? const AttestedValue<double>.empty()
          : AttestedValue(
              value: interrupting,
              sourceType: _interruptingSource,
              citation: _interruptingCitation.text.trim().isEmpty
                  ? null
                  : _interruptingCitation.text.trim(),
              attestation: attestation,
            ),
      currentLimiting: widget.existing.currentLimiting,
      letThrough: widget.existing.letThrough,
      comboRatingIds: widget.existing.comboRatingIds,
      notes: widget.existing.notes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.existing.tag}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _tag,
                        decoration: const InputDecoration(labelText: 'Tag *'))),
                const SizedBox(width: 8),
                SizedBox(
                    width: 70,
                    child: TextField(
                        controller: _quantity,
                        decoration: const InputDecoration(labelText: 'Qty'))),
              ]),
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
                        controller: _manufacturer,
                        decoration:
                            const InputDecoration(labelText: 'Manufacturer'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _partNumber,
                        decoration:
                            const InputDecoration(labelText: 'Part number'))),
              ]),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _volts,
                        decoration: const InputDecoration(
                            labelText: 'Voltage rating (V)'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _sccr,
                        decoration:
                            const InputDecoration(labelText: 'SCCR (kA)'))),
              ]),
              DropdownButtonFormField<SourceType>(
                initialValue: _source,
                decoration:
                    const InputDecoration(labelText: 'SCCR/voltage source'),
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
                      labelText: 'Citation (document, page, date) *')),
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Interrupting rating (distinct from SCCR — never '
                    'substituted)',
                    style: Theme.of(context).textTheme.labelMedium),
              ),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _interrupting,
                        decoration: const InputDecoration(
                            labelText: 'Interrupting rating (kA)'))),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<SourceType>(
                    initialValue: _interruptingSource,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: [
                      for (final s in SourceType.values)
                        DropdownMenuItem(
                            value: s, child: Text(s.wire.replaceAll('_', ' '))),
                    ],
                    onChanged: (v) => setState(
                        () => _interruptingSource = v ?? _interruptingSource),
                  ),
                ),
              ]),
              TextField(
                  controller: _interruptingCitation,
                  decoration: const InputDecoration(
                      labelText: 'Interrupting rating citation')),
              const SizedBox(height: 8),
              Row(children: [
                Checkbox(
                    value: _slashRating,
                    onChanged: (v) =>
                        setState(() => _slashRating = v ?? false)),
                const Text('Slash-rated'),
                const SizedBox(width: 16),
                Checkbox(
                    value: _powerCircuit,
                    onChanged: (v) =>
                        setState(() => _powerCircuit = v ?? true)),
                const Text('Power circuit'),
              ]),
            ],
          ),
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
