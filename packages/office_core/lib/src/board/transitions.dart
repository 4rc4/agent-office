import '../model/task.dart';

/// The task state machine: which status may follow which.
///
/// Terminal states ([TaskStatus.done], [TaskStatus.failed],
/// [TaskStatus.needsHuman]) have no successors.
const Map<TaskStatus, Set<TaskStatus>> legalTransitions = {
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
  TaskStatus.waitingApproval: _fromWaiting,
  TaskStatus.waitingUser: _fromWaiting,
  TaskStatus.waitingBudget: _fromWaiting,
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

const Set<TaskStatus> _fromWaiting = {
  TaskStatus.running,
  TaskStatus.interrupted,
  TaskStatus.failed,
  TaskStatus.needsHuman,
};

/// Whether a task may move from [from] to [to]. A move to the same status is
/// never legal; use a note on an event instead.
bool canTransition(TaskStatus from, TaskStatus to) =>
    legalTransitions[from]?.contains(to) ?? false;

/// Every status that may legally follow [from]; empty for terminal states.
Set<TaskStatus> allowedTransitions(TaskStatus from) =>
    legalTransitions[from] ?? const {};
