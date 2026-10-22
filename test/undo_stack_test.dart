import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/services/undo_stack.dart';

void main() {
  test('undo reverts the most recent edit and reports its label', () async {
    final log = <String>[];
    final stack = UndoStack();

    stack.push(UndoAction(label: 'first', revert: () async => log.add('undo-first')));
    stack.push(UndoAction(label: 'second', revert: () async => log.add('undo-second')));

    expect(stack.canUndo, isTrue);
    expect(stack.lastLabel, 'second');

    expect(await stack.undo(), 'second');
    expect(log, ['undo-second']);
    expect(await stack.undo(), 'first');
    expect(log, ['undo-second', 'undo-first']);

    expect(stack.canUndo, isFalse);
    expect(await stack.undo(), isNull);
  });

  test('the stack never grows past 20 entries', () {
    final stack = UndoStack();
    for (var i = 0; i < 25; i++) {
      stack.push(UndoAction(label: 'edit-$i', revert: () async {}));
    }
    expect(stack.length, UndoStack.maxEntries);
    expect(stack.lastLabel, 'edit-24',
        reason: 'newest edit must survive the cap');
    // The oldest five were dropped: undoing the whole stack never sees them.
    var count = 0;
    while (stack.canUndo) {
      stack.undo();
      count++;
    }
    expect(count, UndoStack.maxEntries);
  });

  test('a revert may guard itself: undo still pops the entry', () async {
    final stack = UndoStack();
    stack.push(UndoAction(
        label: 'guarded', revert: () async {} // decided to do nothing
        ));
    expect(await stack.undo(), 'guarded');
    expect(stack.canUndo, isFalse);
  });

  test('clear drops everything', () async {
    final stack = UndoStack();
    stack.push(UndoAction(label: 'x', revert: () async {}));
    stack.clear();
    expect(stack.canUndo, isFalse);
  });
}
