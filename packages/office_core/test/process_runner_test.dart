import 'dart:io';

import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory bin;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('office_bin_');
  });

  tearDown(() => bin.delete(recursive: true));

  Map<String, String> env() => {
    'PATH': bin.path,
    'PATHEXT': '.COM;.EXE;.BAT;.CMD',
  };

  group('resolveExecutable on Windows', () {
    test('prefers claude.cmd over the extensionless npm shell shim', () {
      File(p.join(bin.path, 'claude')).writeAsStringSync('#!/bin/sh\n');
      File(p.join(bin.path, 'claude.cmd')).writeAsStringSync('@echo off\n');
      expect(
        resolveExecutableOn('claude', environment: env(), isWindows: true),
        p.join(bin.path, 'claude.cmd'),
      );
    });

    test('never picks a file without a PATHEXT extension', () {
      File(p.join(bin.path, 'claude')).writeAsStringSync('#!/bin/sh\n');
      expect(
        resolveExecutableOn('claude', environment: env(), isWindows: true),
        'claude',
      );
    });

    test('tries PATHEXT in order', () {
      File(p.join(bin.path, 'tool.cmd')).writeAsStringSync('');
      File(p.join(bin.path, 'tool.exe')).writeAsStringSync('');
      expect(
        resolveExecutableOn('tool', environment: env(), isWindows: true),
        p.join(bin.path, 'tool.exe'),
      );
    });

    test('keeps a name that already carries a program extension', () {
      File(p.join(bin.path, 'claude.cmd')).writeAsStringSync('');
      expect(
        resolveExecutableOn('claude.cmd', environment: env(), isWindows: true),
        p.join(bin.path, 'claude.cmd'),
      );
    });

    test('returns paths and unknown names unchanged', () {
      expect(
        resolveExecutableOn(
          r'C:\x\claude.cmd',
          environment: env(),
          isWindows: true,
        ),
        r'C:\x\claude.cmd',
      );
      expect(
        resolveExecutableOn('missing', environment: env(), isWindows: true),
        'missing',
      );
    });
  });

  test(
    'resolveExecutable on POSIX takes the bare file from PATH',
    () {
      File(p.join(bin.path, 'claude')).writeAsStringSync('#!/bin/sh\n');
      expect(
        resolveExecutableOn('claude', environment: env(), isWindows: false),
        '${bin.path}/claude',
      );
    },
    // A Windows temp path carries a drive colon, the POSIX PATH separator.
    skip: Platform.isWindows ? 'needs a colon-free PATH' : null,
  );
}
