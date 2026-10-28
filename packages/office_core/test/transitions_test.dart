import 'package:office_core/src/board/transitions.dart';
import 'package:office_core/src/model/task.dart';
import 'package:test/test.dart';

/// The state machine as specified, restated independently of the
/// implementation so a typo in either side shows up.
const Map<TaskStatus, Set<TaskStatus>> _spec = {
  TaskStatus.queued: {
    TaskStatus.planned,
    TaskStatus.assigned,
    TaskStatus.failed,
  },
  TaskStatus.planned: {
    TaskStatus.assigned,
    TaskStatus.waitingBudget,
    TaskStatus.failed,
  },
  TaskStatus.assigned: {
    TaskStatus.running,
    TaskStatus.interrupted,
    TaskStatus.failed,
  },
  TaskStatus.running: {
    TaskStatus.waitingApproval,
    TaskStatus.waitingUser,
    TaskStatus.waitingBudget,
    TaskStatus.review,
    TaskStatus.interrupted,
    TaskStatus.failed,
    TaskStatus.done,
  },
  TaskStatus.waitingApproval: {
    TaskStatus.running,
    TaskStatus.interrupted,
    TaskStatus.failed,
    TaskStatus.needsHuman,
  },
  TaskStatus.waitingUser: {
    TaskStatus.running,
    TaskStatus.interrupted,
    TaskStatus.failed,
    TaskStatus.needsHuman,
  },
  TaskStatus.waitingBudget: {
    TaskStatus.running,
    TaskStatus.interrupted,
    TaskStatus.failed,
    TaskStatus.needsHuman,
  },
  TaskStatus.review: {
    TaskStatus.done,
    TaskStatus.assigned,
    TaskStatus.needsHuman,
    TaskStatus.failed,
  },
  TaskStatus.interrupted: {
    TaskStatus.assigned,
    TaskStatus.running,
    TaskStatus.failed,
    TaskStatus.needsHuman,
  },
  TaskStatus.done: {},
  TaskStatus.failed: {},
  TaskStatus.needsHuman: {},
};

void main() {
  group('canTransition', () {
    test('the spec covers every status', () {
      expect(_spec.keys, containsAll(TaskStatus.values));
    });

    test('allows every legal move', () {
      for (final entry in _spec.entries) {
        for (final to in entry.value) {
          expect(
            canTransition(entry.key, to),
            isTrue,
            reason: '${entry.key.name} -> ${to.name} must be legal',
          );
        }
      }
    });

    test('rejects every move that is not in the table', () {
      for (final from in TaskStatus.values) {
        for (final to in TaskStatus.values) {
          if (_spec[from]!.contains(to)) continue;
          expect(
            canTransition(from, to),
            isFalse,
            reason: '${from.name} -> ${to.name} must be illegal',
          );
        }
      }
    });

    test('terminal states have no successors', () {
      for (final from in TaskStatus.values.where((s) => s.isTerminal)) {
        for (final to in TaskStatus.values) {
          expect(canTransition(from, to), isFalse);
        }
        expect(allowedTransitions(from), isEmpty);
      }
    });

    test('a status never transitions to itself', () {
      for (final status in TaskStatus.values) {
        expect(canTransition(status, status), isFalse);
      }
    });

    test('sample illegal moves', () {
      const samples = [
        (TaskStatus.queued, TaskStatus.running),
        (TaskStatus.queued, TaskStatus.done),
        (TaskStatus.planned, TaskStatus.running),
        (TaskStatus.planned, TaskStatus.review),
        (TaskStatus.assigned, TaskStatus.done),
        (TaskStatus.assigned, TaskStatus.review),
        (TaskStatus.running, TaskStatus.planned),
        (TaskStatus.running, TaskStatus.assigned),
        (TaskStatus.running, TaskStatus.needsHuman),
        (TaskStatus.waitingApproval, TaskStatus.done),
        (TaskStatus.waitingBudget, TaskStatus.review),
        (TaskStatus.review, TaskStatus.running),
        (TaskStatus.interrupted, TaskStatus.done),
        (TaskStatus.done, TaskStatus.assigned),
        (TaskStatus.failed, TaskStatus.queued),
        (TaskStatus.needsHuman, TaskStatus.running),
      ];
      for (final (from, to) in samples) {
        expect(
          canTransition(from, to),
          isFalse,
          reason: '${from.name} -> ${to.name}',
        );
      }
    });

    test('sample legal moves read naturally', () {
      expect(canTransition(TaskStatus.queued, TaskStatus.planned), isTrue);
      expect(canTransition(TaskStatus.planned, TaskStatus.assigned), isTrue);
      expect(canTransition(TaskStatus.assigned, TaskStatus.running), isTrue);
      expect(canTransition(TaskStatus.running, TaskStatus.review), isTrue);
      expect(canTransition(TaskStatus.review, TaskStatus.done), isTrue);
      expect(canTransition(TaskStatus.review, TaskStatus.assigned), isTrue);
      expect(
        canTransition(TaskStatus.interrupted, TaskStatus.assigned),
        isTrue,
      );
      expect(
        canTransition(TaskStatus.waitingUser, TaskStatus.needsHuman),
        isTrue,
      );
    });

    test('allowedTransitions mirrors canTransition', () {
      for (final from in TaskStatus.values) {
        expect(allowedTransitions(from), equals(_spec[from]));
      }
    });
  });
}
