// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// The project workspace (spec §5): circuit tree on the left (primary
// navigation), component entry in the center (keyboard-first), rollup panel
// on the right with the limiting component ("the stray") always visible and
// a single resolve queue for UNRATED/flag states.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'component_editor.dart';
import 'finalize_flow.dart';
import 'trace_view.dart';

class ProjectScreen extends StatefulWidget {
  const ProjectScreen(
      {super.key, required this.state, required this.projectId});

  final AppState state;
  final String projectId;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  AppState get app => widget.state;

  late Project _project;
  late List<Circuit> _circuits;
  late List<Component> _components;
  late RollupResult _result;
  String? _selectedCircuitId;
  String? _highlightComponentId;

  @override
  void initState() {
    super.initState();
    _reload();
    _selectedCircuitId = _circuits.isEmpty ? null : _circuits.first.meta.id;
  }

  void _reload() {
    _project = app.store.getProject(widget.projectId)!;
    _circuits = app.store.circuitsForProject(widget.projectId);
    _components = app.store.componentsForProject(widget.projectId);
    _result = const RollupEngine()
        .evaluate(app.store.loadSnapshot(widget.projectId), app.registry);
  }

  void _refresh() => setState(_reload);

  bool get _editable => _project.status != ProjectStatus.finalized;

  // --- circuit tree -----------------------------------------------------

  List<(Circuit, int)> get _treeRows {
    final byParent = <String?, List<Circuit>>{};
    for (final c in _circuits) {
      byParent.putIfAbsent(c.parentCircuitId, () => []).add(c);
    }
    final rows = <(Circuit, int)>[];
    void walk(String? parent, int depth) {
      for (final c in byParent[parent] ?? const <Circuit>[]) {
        rows.add((c, depth));
        walk(c.meta.id, depth + 1);
      }
    }

    walk(null, 0);
    return rows;
  }

  Future<void> _addCircuit(String? parentId) async {
    final label = await _promptText(context, 'New circuit label');
    if (label == null || label.trim().isEmpty) return;
    final circuit = Circuit(
      meta: newMeta('circ', app.user.meta.id),
      projectId: widget.projectId,
      parentCircuitId: parentId,
      kind: parentId == null ? CircuitKind.feeder : CircuitKind.branch,
      label: label.trim(),
    );
    app.perform(UndoableAction(
      label: 'Add circuit ${circuit.label}',
      redo: () => app.store.saveCircuit(circuit, by: app.user.meta.id),
      undo: () =>
          app.store.deleteCircuit(circuit.meta.id, by: app.user.meta.id),
    ));
    _selectedCircuitId = circuit.meta.id;
    _refresh();
  }

  Future<void> _renameCircuit(Circuit circuit) async {
    final label =
        await _promptText(context, 'Circuit label', initial: circuit.label);
    if (label == null || label.trim().isEmpty) return;
    final renamed = Circuit(
      meta: touch(circuit.meta),
      projectId: circuit.projectId,
      parentCircuitId: circuit.parentCircuitId,
      kind: circuit.kind,
      label: label.trim(),
      upstreamProtectiveDeviceComponentId:
          circuit.upstreamProtectiveDeviceComponentId,
      notes: circuit.notes,
    );
    app.perform(UndoableAction(
      label: 'Rename circuit',
      redo: () => app.store.saveCircuit(renamed, by: app.user.meta.id),
      undo: () => app.store.saveCircuit(circuit, by: app.user.meta.id),
    ));
    _refresh();
  }

  void _deleteCircuit(Circuit circuit) {
    // Deletion cascades; undo restores the whole sub-tree.
    final doomedCircuits = _treeRows
        .where((row) =>
            row.$1.meta.id == circuit.meta.id ||
            _isDescendant(row.$1, circuit.meta.id))
        .map((row) => row.$1)
        .toList();
    final doomedIds = doomedCircuits.map((c) => c.meta.id).toSet();
    final doomedComponents =
        _components.where((c) => doomedIds.contains(c.circuitId)).toList();
    app.perform(UndoableAction(
      label: 'Delete circuit ${circuit.label}',
      redo: () =>
          app.store.deleteCircuit(circuit.meta.id, by: app.user.meta.id),
      undo: () {
        for (final c in doomedCircuits) {
          app.store.saveCircuit(c, by: app.user.meta.id);
        }
        for (final c in doomedComponents) {
          app.store.saveComponent(c,
              projectId: widget.projectId, by: app.user.meta.id);
        }
      },
    ));
    if (doomedIds.contains(_selectedCircuitId)) _selectedCircuitId = null;
    _refresh();
  }

  bool _isDescendant(Circuit circuit, String ancestorId) {
    final byId = {for (final c in _circuits) c.meta.id: c};
    var parent = circuit.parentCircuitId;
    while (parent != null) {
      if (parent == ancestorId) return true;
      parent = byId[parent]?.parentCircuitId;
    }
    return false;
  }

  // --- component actions -------------------------------------------------

  void _saveComponent(Component component, {Component? previous}) {
    app.perform(UndoableAction(
      label: previous == null
          ? 'Add component ${component.tag}'
          : 'Edit component ${component.tag}',
      redo: () => app.store.saveComponent(component,
          projectId: widget.projectId, by: app.user.meta.id),
      undo: () {
        if (previous == null) {
          app.store.deleteComponent(component.meta.id, by: app.user.meta.id);
        } else {
          app.store.saveComponent(previous,
              projectId: widget.projectId, by: app.user.meta.id);
        }
      },
    ));
    _refresh();
  }

  void _deleteComponent(Component component) {
    app.perform(UndoableAction(
      label: 'Delete component ${component.tag}',
      redo: () =>
          app.store.deleteComponent(component.meta.id, by: app.user.meta.id),
      undo: () => app.store.saveComponent(component,
          projectId: widget.projectId, by: app.user.meta.id),
    ));
    _refresh();
  }

  void _duplicateComponent(Component source) {
    final copy = Component(
      meta: newMeta('comp', app.user.meta.id),
      circuitId: source.circuitId,
      libraryItemId: source.libraryItemId,
      libraryItemVersion: source.libraryItemVersion,
      quantity: source.quantity,
      tag: '${source.tag}-copy',
      category: source.category,
      categoryOtherLabel: source.categoryOtherLabel,
      manufacturer: source.manufacturer,
      partNumber: source.partNumber,
      powerCircuit: source.powerCircuit,
      voltageRating: source.voltageRating,
      sccrKa: source.sccrKa,
      interruptingRatingKa: source.interruptingRatingKa,
      currentLimiting: source.currentLimiting,
      letThrough: source.letThrough,
      comboRatingIds: source.comboRatingIds,
      notes: source.notes,
    );
    _saveComponent(copy);
  }

  void _jumpTo(String? componentId, String? circuitId) {
    setState(() {
      if (circuitId != null) _selectedCircuitId = circuitId;
      _highlightComponentId = componentId;
    });
  }

  // --- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selectedComponents = _components
        .where((c) => c.circuitId == _selectedCircuitId)
        .toList()
      ..sort((a, b) => a.tag.compareTo(b.tag));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          app.undo();
          _refresh();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): () {
          app.redo();
          _refresh();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text('${_project.name}  ·  rev ${_project.revision ?? '-'}'
                '${_editable ? '' : '  ·  FINALIZED'}'),
            actions: [
              IconButton(
                tooltip: app.canUndo ? 'Undo ${app.undoLabel}' : 'Undo',
                icon: const Icon(Icons.undo),
                onPressed: app.canUndo
                    ? () {
                        app.undo();
                        _refresh();
                      }
                    : null,
              ),
              IconButton(
                tooltip: app.canRedo ? 'Redo ${app.redoLabel}' : 'Redo',
                icon: const Icon(Icons.redo),
                onPressed: app.canRedo
                    ? () {
                        app.redo();
                        _refresh();
                      }
                    : null,
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 280, child: _buildTree()),
              const VerticalDivider(width: 1),
              Expanded(child: _buildCenter(selectedComponents)),
              const VerticalDivider(width: 1),
              SizedBox(width: 360, child: _buildRollupPanel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTree() {
    final rows = _treeRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Text('Circuits', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (_editable)
                IconButton(
                  tooltip: 'Add root feeder circuit',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addCircuit(null),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final (circuit, depth) in rows)
                InkWell(
                  onTap: () =>
                      setState(() => _selectedCircuitId = circuit.meta.id),
                  child: Container(
                    color: circuit.meta.id == _selectedCircuitId
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    padding: EdgeInsets.only(
                        left: 8.0 + depth * 16, top: 4, bottom: 4, right: 4),
                    child: Row(
                      children: [
                        Icon(
                          circuit.kind == CircuitKind.feeder
                              ? Icons.bolt
                              : Icons.account_tree_outlined,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${circuit.label}'
                            ' (${_components.where((c) => c.circuitId == circuit.meta.id).length})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_editable)
                          PopupMenuButton<String>(
                            iconSize: 16,
                            onSelected: (choice) => switch (choice) {
                              'add' => _addCircuit(circuit.meta.id),
                              'rename' => _renameCircuit(circuit),
                              'delete' => _deleteCircuit(circuit),
                              _ => null,
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: 'add', child: Text('Add sub-circuit')),
                              PopupMenuItem(
                                  value: 'rename', child: Text('Rename')),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete (with contents)')),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenter(List<Component> components) {
    if (_selectedCircuitId == null) {
      return const Center(child: Text('Select a circuit to add components.'));
    }
    return Column(
      children: [
        Expanded(
          child: components.isEmpty
              ? const Center(
                  child: Text(
                      'No components on this circuit yet.\nUse the entry '
                      'form below — Tab moves between fields, Enter saves '
                      'and keeps going.',
                      textAlign: TextAlign.center),
                )
              : ListView(
                  children: [
                    for (final component in components)
                      _ComponentRow(
                        component: component,
                        highlighted: component.meta.id == _highlightComponentId,
                        editable: _editable,
                        onEdit: () async {
                          final edited = await showComponentEditorDialog(
                            context,
                            state: app,
                            circuitId: component.circuitId,
                            existing: component,
                          );
                          if (edited != null) {
                            _saveComponent(edited, previous: component);
                          }
                        },
                        onDuplicate: () => _duplicateComponent(component),
                        onDelete: () => _deleteComponent(component),
                      ),
                  ],
                ),
        ),
        if (_editable) ...[
          const Divider(height: 1),
          ComponentEntryForm(
            key: ValueKey(_selectedCircuitId),
            state: app,
            circuitId: _selectedCircuitId!,
            onCommit: _saveComponent,
          ),
        ],
      ],
    );
  }

  Widget _buildRollupPanel() {
    final panelValues = _result.panelSccrKaByVoltage;
    final blockers =
        _result.flags.where((f) => f.severity == FlagSeverity.blocker).toList();
    final warnings =
        _result.flags.where((f) => f.severity == FlagSeverity.warning).toList();
    final questions = _result.flags
        .where((f) => f.severity == FlagSeverity.question)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Panel SCCR (as entered and attested)',
            style: Theme.of(context).textTheme.titleSmall),
        for (final entry in panelValues.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              entry.value == null
                  ? '${entry.key.replaceAll('_', ' ')}: — (unresolved)'
                  : '${entry.key.replaceAll('_', ' ')}: '
                      '${entry.value!.toStringAsFixed(1)} kA',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        if (_result.containsUnverifiedRuleResults)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Text('CONTAINS UNVERIFIED RULES — NOT FOR USE\n'
                  'One or more rules that fired are not signed off in the '
                  'rules registry. Reports stay watermarked and the project '
                  'cannot be finalized.'),
            ),
          ),
        const SizedBox(height: 8),
        Text('The strays (limiting components)',
            style: Theme.of(context).textTheme.titleSmall),
        if (_result.limitingComponents.isEmpty)
          const Text('None yet.')
        else
          for (final stray in _result.limitingComponents)
            ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber, size: 18),
              title: Text(
                  '${stray.tag} — ${stray.effectiveSccrKa.toStringAsFixed(1)} kA'),
              onTap: () {
                final matches = _components
                    .where((c) => c.meta.id == stray.componentId)
                    .toList();
                _jumpTo(stray.componentId,
                    matches.isEmpty ? null : matches.first.circuitId);
              },
            ),
        const Divider(),
        Text('Resolve queue', style: Theme.of(context).textTheme.titleSmall),
        _flagList('Blockers', blockers, Colors.red),
        _flagList('Warnings', warnings, Colors.orange),
        _flagList('Questions', questions, Colors.blueGrey),
        const Divider(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.travel_explore),
              label: const Text('Value traces'),
              onPressed: () => showTraceView(context, _result),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Draft report'),
              onPressed: () => generateReport(context,
                  state: app, projectId: widget.projectId, draft: true),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.lock_outline),
              label: const Text('Finalize…'),
              onPressed: _editable
                  ? () async {
                      await showFinalizeFlow(context,
                          state: app, projectId: widget.projectId);
                      _refresh();
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _flagList(String title, List<EngineFlag> flags, Color color) {
    if (flags.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('$title (${flags.length})',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        for (final flag in flags)
          ListTile(
            dense: true,
            leading: Icon(Icons.flag, size: 16, color: color),
            title: Text(flag.message, style: const TextStyle(fontSize: 12)),
            subtitle: Text('rule ${flag.ruleId} v${flag.ruleVersion}',
                style: const TextStyle(fontSize: 10)),
            onTap: flag.componentId == null
                ? null
                : () => _jumpTo(flag.componentId, flag.circuitId),
          ),
      ],
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.component,
    required this.highlighted,
    required this.editable,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Component component;
  final bool highlighted;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sccr = component.sccrKa;
    return Container(
      color:
          highlighted ? Theme.of(context).colorScheme.tertiaryContainer : null,
      child: ListTile(
        dense: true,
        leading: component.isUnrated
            ? const Tooltip(
                message: 'UNRATED — blocks finalization until resolved',
                child: Icon(Icons.error_outline, color: Colors.red),
              )
            : const Icon(Icons.check_circle_outline, size: 18),
        title: Text(
            '${component.tag} · ${component.category.wire.replaceAll('_', ' ')}'
            '${component.quantity > 1 ? ' ×${component.quantity}' : ''}'),
        subtitle: Text([
          if (component.manufacturer != null) component.manufacturer!,
          if (component.partNumber != null) component.partNumber!,
          if (component.voltageRating.value != null)
            '${component.voltageRating.value!.volts.toStringAsFixed(0)} V',
          component.isUnrated
              ? 'UNRATED'
              : '${sccr.value!.toStringAsFixed(1)} kA '
                  '(${sccr.sourceType!.wire})',
          if (!component.powerCircuit) 'control circuit',
        ].join(' · ')),
        trailing: editable
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: onEdit),
                  IconButton(
                      tooltip: 'Duplicate row',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: onDuplicate),
                  IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: onDelete),
                ],
              )
            : null,
        onTap: editable ? onEdit : null,
      ),
    );
  }
}

Future<String?> _promptText(BuildContext context, String title,
    {String? initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('OK')),
      ],
    ),
  );
}
