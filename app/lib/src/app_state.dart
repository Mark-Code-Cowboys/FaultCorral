// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:faultcorral_store/faultcorral_store.dart';
import 'package:flutter/foundation.dart';

const appVersion = '0.1.0-phase1';

int _idSeq = 0;

/// App-local id generation; uniqueness within this shop is all that is
/// required of ids (core treats them as opaque).
Id newId(String prefix) =>
    '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-${_idSeq++}';

EntityMeta newMeta(String prefix, Id by) {
  final now = DateTime.now().toUtc();
  return EntityMeta(
      id: newId(prefix), createdAt: now, updatedAt: now, createdBy: by);
}

EntityMeta touch(EntityMeta meta) => EntityMeta(
      id: meta.id,
      createdAt: meta.createdAt,
      updatedAt: DateTime.now().toUtc(),
      createdBy: meta.createdBy,
    );

/// One reversible user action (spec §5: undo/redo across the project).
class UndoableAction {
  UndoableAction({required this.label, required this.redo, required this.undo});

  final String label;
  final VoidCallback redo;
  final VoidCallback undo;
}

/// Session-wide state: the store, the local shop/user identity, and the
/// undo/redo stacks. Multi-user roles arrive in Phase 3; Phase 1 runs as a
/// single local user with the owner role.
class AppState extends ChangeNotifier {
  AppState({required this.store, required this.shop, required this.user});

  final FaultCorralStore store;
  final Shop shop;
  final User user;

  final List<UndoableAction> _undoStack = [];
  final List<UndoableAction> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  String? get undoLabel => canUndo ? _undoStack.last.label : null;
  String? get redoLabel => canRedo ? _redoStack.last.label : null;

  /// Executes [action] and records it for undo.
  void perform(UndoableAction action) {
    action.redo();
    _undoStack.add(action);
    _redoStack.clear();
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final action = _undoStack.removeLast();
    action.undo();
    _redoStack.add(action);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final action = _redoStack.removeLast();
    action.redo();
    _undoStack.add(action);
    notifyListeners();
  }

  /// Undo history is per-project workspace; clear when switching.
  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  RulesRegistry get registry =>
      store.registryForShop(shop.meta.id, by: user.meta.id);
}
