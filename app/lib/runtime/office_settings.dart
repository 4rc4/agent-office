import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What the window needs to build an office: where the agents work, which
/// binaries they are, and whether vendor output is faked. Stored as JSON in
/// `settings.json` under the app support folder (see [settingsDirectory]).
class OfficeSettings {
  const OfficeSettings({
    required this.cwd,
    this.claudeExecutable = 'claude',
    this.codexExecutable = 'codex',
    this.permissionMode = 'acceptEdits',
    this.fake = false,
    this.brainFile,
    this.fixturesDir,
  });

  /// Defaults with the current folder as the repository.
  factory OfficeSettings.defaults() =>
      OfficeSettings(cwd: Directory.current.path);

  /// Reads settings from [json]; missing or mistyped fields fall back to the
  /// defaults, so an old or hand-edited file never blocks start-up.
  factory OfficeSettings.fromJson(Map<String, Object?> json) {
    final defaults = OfficeSettings.defaults();
    String text(String key, String fallback) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value : fallback;
    }

    String? optional(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    return OfficeSettings(
      cwd: text('cwd', defaults.cwd),
      claudeExecutable: text('claudeExecutable', defaults.claudeExecutable),
      codexExecutable: text('codexExecutable', defaults.codexExecutable),
      permissionMode: text('permissionMode', defaults.permissionMode),
      fake: json['fake'] is bool ? json['fake'] as bool : defaults.fake,
      brainFile: optional('brainFile'),
      fixturesDir: optional('fixturesDir'),
    );
  }

  /// File name inside the settings directory.
  static const String fileName = 'settings.json';

  /// The repository the agents work in.
  final String cwd;

  /// The `claude` binary; a bare name is looked up on PATH.
  final String claudeExecutable;

  /// The `codex` binary.
  final String codexExecutable;

  /// Claude `--permission-mode` for brain and worker runs.
  final String permissionMode;

  /// Replay fixtures instead of launching the vendor CLIs.
  final bool fake;

  /// Brain system prompt file; null uses the bundled `brain/brain.md`.
  final String? brainFile;

  /// Folder with office_core's fake fixtures (only read when [fake] is on);
  /// null lets office_core look next to its own package, which works from
  /// source but not from a built app.
  final String? fixturesDir;

  Map<String, Object?> toJson() => {
    'cwd': cwd,
    'claudeExecutable': claudeExecutable,
    'codexExecutable': codexExecutable,
    'permissionMode': permissionMode,
    'fake': fake,
    'brainFile': brainFile,
    'fixturesDir': fixturesDir,
  };

  OfficeSettings copyWith({
    String? cwd,
    String? claudeExecutable,
    String? codexExecutable,
    String? permissionMode,
    bool? fake,
    String? brainFile,
    bool clearBrainFile = false,
    String? fixturesDir,
    bool clearFixturesDir = false,
  }) {
    return OfficeSettings(
      cwd: cwd ?? this.cwd,
      claudeExecutable: claudeExecutable ?? this.claudeExecutable,
      codexExecutable: codexExecutable ?? this.codexExecutable,
      permissionMode: permissionMode ?? this.permissionMode,
      fake: fake ?? this.fake,
      brainFile: clearBrainFile ? null : (brainFile ?? this.brainFile),
      fixturesDir: clearFixturesDir ? null : (fixturesDir ?? this.fixturesDir),
    );
  }

  /// The platform's application support folder, created when missing.
  static Future<String> settingsDirectory() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Loads `settings.json` from [directory] (default: [settingsDirectory]).
  /// A missing, unreadable or corrupt file yields [OfficeSettings.defaults].
  static Future<OfficeSettings> load({String? directory}) async {
    final file = File(p.join(directory ?? await settingsDirectory(), fileName));
    try {
      if (!file.existsSync()) return OfficeSettings.defaults();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return OfficeSettings.defaults();
      return OfficeSettings.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return OfficeSettings.defaults();
    } on IOException {
      return OfficeSettings.defaults();
    }
  }

  /// Writes `settings.json` into [directory] (default: [settingsDirectory]),
  /// creating the folder when needed. Returns the file written.
  Future<File> save({String? directory}) async {
    final dir = directory ?? await settingsDirectory();
    await Directory(dir).create(recursive: true);
    final file = File(p.join(dir, fileName));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(toJson())}\n');
    return file;
  }

  @override
  bool operator ==(Object other) =>
      other is OfficeSettings &&
      other.cwd == cwd &&
      other.claudeExecutable == claudeExecutable &&
      other.codexExecutable == codexExecutable &&
      other.permissionMode == permissionMode &&
      other.fake == fake &&
      other.brainFile == brainFile &&
      other.fixturesDir == fixturesDir;

  @override
  int get hashCode => Object.hash(
    cwd,
    claudeExecutable,
    codexExecutable,
    permissionMode,
    fake,
    brainFile,
    fixturesDir,
  );

  @override
  String toString() => 'OfficeSettings(${jsonEncode(toJson())})';
}
