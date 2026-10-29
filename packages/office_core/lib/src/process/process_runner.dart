import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thin seam over `Process.start` so adapters can be tested with scripted
/// output and so the real runner can hold the Windows rules in one place
/// (absolute executable paths, `cmd /c` for npm shims, scrubbed environment).
abstract class ProcessRunner {
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

abstract class RunningProcess {
  Stream<String> get stdoutLines;
  Stream<String> get stderrLines;
  Future<int> get exitCode;

  /// Write one line to the child's stdin (a newline is appended).
  void writeLine(String line);

  /// Close stdin: the polite stop. Claude finishes the turn and exits.
  Future<void> closeStdin();

  /// Hard stop. On Windows this is TerminateProcess; the child gets no signal.
  bool kill();
}

/// Environment variables that must never reach a vendor CLI: with any of them
/// set, `claude` or `codex` would bill an API key instead of using the
/// subscription login. The runner removes them even when the Office process
/// itself inherited them.
const Set<String> scrubbedEnvironmentKeys = {
  'ANTHROPIC_API_KEY',
  'ANTHROPIC_AUTH_TOKEN',
  'CLAUDE_CODE_USE_BEDROCK',
  'CLAUDE_CODE_USE_VERTEX',
  'OPENAI_API_KEY',
  'CODEX_API_KEY',
};

class DartProcessRunner implements ProcessRunner {
  const DartProcessRunner({this.scrubKeys = scrubbedEnvironmentKeys});

  final Set<String> scrubKeys;

  /// The environment a child gets: the parent's, with [environment] layered
  /// on top and [scrubKeys] removed. Exposed for tests.
  Map<String, String> childEnvironment(Map<String, String>? environment) {
    final merged = <String, String>{...Platform.environment, ...?environment};
    merged.removeWhere((key, _) => scrubKeys.contains(key.toUpperCase()));
    return merged;
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      resolveExecutable(executable, environment: environment),
      arguments,
      workingDirectory: workingDirectory,
      environment: childEnvironment(environment),
      includeParentEnvironment: false,
      runInShell: false,
    );
    return _DartRunningProcess(process);
  }
}

/// Turns a bare command name into the file Process.start can launch.
///
/// Without a shell, Windows only finds `.exe` files; npm installs `claude`
/// and `codex` as `claude.cmd` / `codex.cmd`, so a bare name fails with
/// "The system cannot find the file specified". This walks PATH (from
/// [environment] or the process) and tries every PATHEXT extension, the way
/// cmd.exe would. A name that contains a path separator is returned
/// unchanged; so is a name that is not found (Process.start then reports
/// the real error).
///
/// npm also drops an extensionless `claude` next to `claude.cmd`: the POSIX
/// shell shim. cmd.exe never runs that file (a name without one of the
/// PATHEXT extensions is not a program), and CreateProcess rejects it with
/// "%1 is not a valid Win32 application", so on Windows the bare name only
/// counts when it already ends in a PATHEXT extension.
String resolveExecutable(String name, {Map<String, String>? environment}) {
  return _resolveExecutable(
    name,
    environment: {...Platform.environment, ...?environment},
    isWindows: Platform.isWindows,
  );
}

/// [resolveExecutable] with the platform pinned, for tests.
String resolveExecutableOn(
  String name, {
  required Map<String, String> environment,
  required bool isWindows,
}) => _resolveExecutable(name, environment: environment, isWindows: isWindows);

String _resolveExecutable(
  String name, {
  required Map<String, String> environment,
  required bool isWindows,
}) {
  if (name.contains('/') || name.contains(r'\')) return name;
  final pathExtensions = isWindows
      ? (environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD')
            .split(';')
            .where((e) => e.isNotEmpty)
            .map((e) => e.toLowerCase())
            .toList()
      : const <String>[];
  final lower = name.toLowerCase();
  final hasProgramExtension =
      !isWindows || pathExtensions.any((ext) => lower.endsWith(ext));
  if (hasProgramExtension && File(name).existsSync()) return name;
  final extensions = [if (hasProgramExtension) '', ...pathExtensions];
  final pathValue = environment['PATH'] ?? environment['Path'] ?? '';
  final pathSeparator = isWindows ? ';' : ':';
  final fileSeparator = isWindows ? r'\' : '/';
  for (final dir in pathValue.split(pathSeparator)) {
    if (dir.isEmpty) continue;
    for (final ext in extensions) {
      final candidate = '$dir$fileSeparator$name$ext';
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return name;
}

class _DartRunningProcess implements RunningProcess {
  _DartRunningProcess(this._process)
    : stdoutLines = _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream(),
      stderrLines = _process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

  final Process _process;

  @override
  final Stream<String> stdoutLines;
  @override
  final Stream<String> stderrLines;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void writeLine(String line) => _process.stdin.writeln(line);

  @override
  Future<void> closeStdin() => _process.stdin.close();

  @override
  bool kill() => _process.kill();
}

/// Scripted process for tests: emits the given stdout lines in order, then
/// exits with [exitCode]. Lines written to stdin are recorded in [stdinLines].
class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner(this.scripts);

  /// Keyed by executable basename; each start pops the next script.
  final Map<String, List<FakeScript>> scripts;
  final List<FakeStart> starts = [];

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final key = executable.split(RegExp(r'[\\/]')).last;
    final queue = scripts[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('FakeProcessRunner: no script left for $key');
    }
    final script = queue.removeAt(0);
    final process = FakeRunningProcess(script);
    starts.add(
      FakeStart(executable, arguments, workingDirectory, environment, process),
    );
    return process;
  }
}

class FakeScript {
  const FakeScript(
    this.stdoutLines, {
    this.exitCode = 0,
    this.stderrLines = const [],
  });

  final List<String> stdoutLines;
  final List<String> stderrLines;
  final int exitCode;
}

class FakeStart {
  const FakeStart(
    this.executable,
    this.arguments,
    this.workingDirectory,
    this.environment,
    this.process,
  );

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final FakeRunningProcess process;
}

class FakeRunningProcess implements RunningProcess {
  FakeRunningProcess(FakeScript script) : _script = script {
    // Emit only after the event loop has turned once, so a caller that
    // subscribes right after `await runner.start(...)` sees every line.
    scheduleMicrotask(() async {
      await Future<void>.delayed(Duration.zero);
      for (final line in _script.stderrLines) {
        if (killed) break;
        _stderr.add(line);
      }
      for (final line in _script.stdoutLines) {
        if (killed) break;
        _stdout.add(line);
        await Future<void>.delayed(Duration.zero);
      }
      await _stdout.close();
      await _stderr.close();
      if (!_exit.isCompleted) _exit.complete(_script.exitCode);
    });
  }

  final FakeScript _script;
  final _stdout = StreamController<String>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final _exit = Completer<int>();
  final List<String> stdinLines = [];
  bool stdinClosed = false;
  bool killed = false;

  @override
  Stream<String> get stdoutLines => _stdout.stream;
  @override
  Stream<String> get stderrLines => _stderr.stream;
  @override
  Future<int> get exitCode => _exit.future;

  @override
  void writeLine(String line) => stdinLines.add(line);

  @override
  Future<void> closeStdin() async => stdinClosed = true;

  @override
  bool kill() {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(143);
    return true;
  }
}
