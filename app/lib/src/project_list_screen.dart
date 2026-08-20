// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'dart:typed_data';

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'defaults_screen.dart';
import 'library_screen.dart';
import 'project_screen.dart';
import 'registry_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  AppState get app => widget.state;

  List<Project> get _projects => app.store.projectsForShop(app.shop.meta.id);

  Future<void> _createProject() async {
    final created = await showDialog<Project>(
      context: context,
      builder: (context) => _NewProjectDialog(state: app),
    );
    if (created == null || !mounted) return;
    setState(() {});
    await _open(created);
  }

  Future<void> _open(Project project) async {
    app.clearHistory();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) =>
          ProjectScreen(state: app, projectId: project.meta.id),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'FaultCorral project', extensions: ['json']),
    ]);
    if (file == null) return;
    try {
      final id = app.store
          .importProject(await file.readAsString(), by: app.user.meta.id);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Imported project $id.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _export(Project project) async {
    final location = await getSaveLocation(
      suggestedName: '${project.name.replaceAll(' ', '_')}.faultcorral.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'FaultCorral project', extensions: ['json']),
      ],
    );
    if (location == null) return;
    final json = app.store.exportProject(project.meta.id,
        by: app.user.meta.id, appVersion: appVersion);
    await XFile.fromData(
      Uint8List.fromList(json.codeUnits),
      mimeType: 'application/json',
    ).saveTo(location.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Exported to ${location.path}')));
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FaultCorral'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Library'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (context) => LibraryScreen(state: app))),
          ),
          TextButton.icon(
            icon: const Icon(Icons.tune),
            label: const Text('Assumed ratings'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (context) => DefaultsScreen(state: app))),
          ),
          TextButton.icon(
            icon: const Icon(Icons.rule),
            label: const Text('Rules registry'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (context) => RegistryScreen(state: app))),
          ),
          IconButton(
            tooltip: 'Import project file',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: _import,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        icon: const Icon(Icons.add),
        label: const Text('New project'),
      ),
      body: projects.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.electrical_services, size: 56),
                  const SizedBox(height: 12),
                  Text('No projects yet.',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text('Create a panel project to start your SCCR '
                      'determination worksheet.'),
                ],
              ),
            )
          : ListView(
              children: [
                for (final project in projects)
                  ListTile(
                    leading: Icon(project.status == ProjectStatus.finalized
                        ? Icons.lock_outline
                        : Icons.edit_note),
                    title: Text(project.name),
                    subtitle: Text([
                      if (project.panelNumber != null)
                        'Panel ${project.panelNumber}',
                      if (project.customer != null) project.customer!,
                      project.ratedVoltages
                          .map((rv) => '${rv.volts.toStringAsFixed(0)} V')
                          .join(', '),
                    ].join(' · ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(label: Text(project.status.wire)),
                        IconButton(
                          tooltip: 'Export portable project file (backup)',
                          icon: const Icon(Icons.save_alt),
                          onPressed: () => _export(project),
                        ),
                      ],
                    ),
                    onTap: () => _open(project),
                  ),
              ],
            ),
    );
  }
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.state});

  final AppState state;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _name = TextEditingController();
  final _customer = TextEditingController();
  final _panelNumber = TextEditingController();
  final _volts = TextEditingController(text: '480');
  VoltageSystem _system = VoltageSystem.threePhaseWye;
  bool _slashContext = false;

  @override
  void dispose() {
    _name.dispose();
    _customer.dispose();
    _panelNumber.dispose();
    _volts.dispose();
    super.dispose();
  }

  void _create() {
    final volts = double.tryParse(_volts.text);
    if (_name.text.trim().isEmpty || volts == null) return;
    final app = widget.state;
    final project = Project(
      meta: newMeta('proj', app.user.meta.id),
      shopId: app.shop.meta.id,
      name: _name.text.trim(),
      customer: _customer.text.trim().isEmpty ? null : _customer.text.trim(),
      panelNumber:
          _panelNumber.text.trim().isEmpty ? null : _panelNumber.text.trim(),
      revision: 'A',
      status: ProjectStatus.draft,
      ratedVoltages: [
        RatedVoltage(
            volts: volts, system: _system, slashRatingContext: _slashContext),
      ],
    );
    app.store.saveProject(project, by: app.user.meta.id);
    // Every panel starts with its incoming feeder as the tree root.
    app.store.saveCircuit(
      Circuit(
        meta: newMeta('circ', app.user.meta.id),
        projectId: project.meta.id,
        kind: CircuitKind.feeder,
        label: 'Incoming feeder',
      ),
      by: app.user.meta.id,
    );
    Navigator.of(context).pop(project);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New panel project'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Project name *'),
            ),
            TextField(
              controller: _customer,
              decoration: const InputDecoration(labelText: 'Customer'),
            ),
            TextField(
              controller: _panelNumber,
              decoration:
                  const InputDecoration(labelText: 'Panel / drawing number'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _volts,
                    decoration:
                        const InputDecoration(labelText: 'Rated voltage (V) *'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<VoltageSystem>(
                  value: _system,
                  items: [
                    for (final s in VoltageSystem.values)
                      DropdownMenuItem(
                          value: s, child: Text(s.wire.replaceAll('_', ' '))),
                  ],
                  onChanged: (v) => setState(() => _system = v ?? _system),
                ),
              ],
            ),
            CheckboxListTile(
              value: _slashContext,
              onChanged: (v) => setState(() => _slashContext = v ?? false),
              title: const Text('Slash-rating context applies'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }
}
