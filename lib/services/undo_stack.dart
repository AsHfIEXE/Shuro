import 'package:flutter/foundation.dart';

/// One reversible edit. [revert] must restore the previous state exactly and
/// must not rely on anything being mounted — it can run long after the screen
/// that triggered the edit is gone.
class UndoAction {
  final String label;

  final Future<void> Function() revert;

  const UndoAction({required this.label, required this.revert});
}

/// A bounded stack of reversible edits (roadmap #29).
///
/// Undo only, no redo: a redo stack doubles the states every hook must
/// capture, and every action here is also cheap to redo by hand. The stack is
/// in-memory by design — replaying yesterday's edits after a restart would
/// surprise more than it helps.
class UndoStack extends ChangeNotifier {
  static const int maxEntries = 20;

  final List<UndoAction> _actions = <UndoAction>[];

  bool get canUndo => _actions.isNotEmpty;

  int get length => _actions.length;

  /// Label of the edit undo would revert — shown on the undo entry point.
  String? get lastLabel => _actions.isEmpty ? null : _actions.last.label;

  void push(UndoAction action) {
    _actions.add(action);
    if (_actions.length > maxEntries) _actions.removeAt(0);
    notifyListeners();
  }

  /// Reverts the most recent edit. Returns its label so the UI can confirm
  /// what was undone, or null when there was nothing to undo.
  Future<String?> undo() async {
    if (_actions.isEmpty) return null;
    final action = _actions.removeLast();
    await action.revert();
    notifyListeners();
    return action.label;
  }

  void clear() {
    if (_actions.isEmpty) return;
    _actions.clear();
    notifyListeners();
  }
}
