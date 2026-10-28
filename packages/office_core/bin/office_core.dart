import 'dart:io';

import 'package:office_core/office_core.dart';

/// Entry point: `dart run bin/office_core.dart run "<prompt>" --cwd <dir>`
/// or `... reconcile --db <file>`; see [cliUsage]. All logic lives in
/// [runCli] so tests can drive the same wiring without spawning a process.
Future<void> main(List<String> arguments) async {
  final code = await runCli(arguments, out: stdout, err: stderr);
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
