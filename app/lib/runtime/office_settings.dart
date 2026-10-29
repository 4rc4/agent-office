import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:office_core/office_core.dart';
import 'package:path_provider/path_provider.dart';

import '../desktop/model_choices.dart';

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
    this.stationPositions = const {},
    this.recentFolders = const [],
    this.claudeModel = '',
    this.claudeEffort = '',
    this.codexModel = '',
    this.codexEffort = '',
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

    final positions = <String, double>{};
    final rawPositions = json['stationPositions'];
    if (rawPositions is Map) {
      for (final entry in rawPositions.entries) {
        final value = entry.value;
        if (entry.key is String && value is num) {
          // The TV took the coffee machine's place (and its saved spot).
          final key = entry.key == 'coffee' ? 'tv' : entry.key as String;
          positions.putIfAbsent(key, () => value.toDouble());
        }
      }
    }
    final rawFolders = json['recentFolders'];
    final folders = rawFolders is List
        ? [
            for (final f in rawFolders)
              if (f is String && f.trim().isNotEmpty) f,
          ]
        : const <String>[];

    return OfficeSettings(
      cwd: text('cwd', defaults.cwd),
      claudeExecutable: text('claudeExecutable', defaults.claudeExecutable),
      codexExecutable: text('codexExecutable', defaults.codexExecutable),
      permissionMode: text('permissionMode', defaults.permissionMode),
      fake: json['fake'] is bool ? json['fake'] as bool : defaults.fake,
      brainFile: optional('brainFile'),
      fixturesDir: optional('fixturesDir'),
      stationPositions: positions,
      recentFolders: folders,
      claudeModel: text('claudeModel', ''),
      claudeEffort: text('claudeEffort', ''),
      codexModel: text('codexModel', ''),
      codexEffort: text('codexEffort', ''),
    );
  }

  /// How many folders [recentFolders] keeps.
  static const int maxRecentFolders = 5;

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

  /// Where the desktop stations stand: station name to the centre's
  /// fraction of the screen width (0..1). Missing stations use defaults.
  final Map<String, double> stationPositions;

  /// Folders the user sent prompts in, most recent first, at most
  /// [maxRecentFolders].
  final List<String> recentFolders;

  /// Default model and effort per seat (`--model`/`--effort` for Claude,
  /// `-m`/`model_reasoning_effort` for Codex); empty leaves the CLI's own.
  final String claudeModel;
  final String claudeEffort;
  final String codexModel;
  final String codexEffort;

  /// The prompt options a bubble for [seat] starts with.
  PromptOptions defaultOptions(Seat seat) => seat == Seat.gpt
      ? PromptOptions(model: codexModel, effort: codexEffort)
      : PromptOptions(model: claudeModel, effort: claudeEffort);

  /// [recentFolders] with [folder] moved to the front.
  List<String> withRecentFolder(String folder) => [
    folder,
    for (final f in recentFolders)
      if (f != folder) f,
  ].take(maxRecentFolders).toList();

  Map<String, Object?> toJson() => {
    'cwd': cwd,
    'claudeExecutable': claudeExecutable,
    'codexExecutable': codexExecutable,
    'permissionMode': permissionMode,
    'fake': fake,
    'brainFile': brainFile,
    'fixturesDir': fixturesDir,
    'stationPositions': stationPositions,
    'recentFolders': recentFolders,
    'claudeModel': claudeModel,
    'claudeEffort': claudeEffort,
    'codexModel': codexModel,
    'codexEffort': codexEffort,
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
    Map<String, double>? stationPositions,
    List<String>? recentFolders,
    String? claudeModel,
    String? claudeEffort,
    String? codexModel,
    String? codexEffort,
  }) {
    return OfficeSettings(
      cwd: cwd ?? this.cwd,
      claudeExecutable: claudeExecutable ?? this.claudeExecutable,
      codexExecutable: codexExecutable ?? this.codexExecutable,
      permissionMode: permissionMode ?? this.permissionMode,
      fake: fake ?? this.fake,
      brainFile: clearBrainFile ? null : (brainFile ?? this.brainFile),
      fixturesDir: clearFixturesDir ? null : (fixturesDir ?? this.fixturesDir),
      stationPositions: stationPositions ?? this.stationPositions,
      recentFolders: recentFolders ?? this.recentFolders,
      claudeModel: claudeModel ?? this.claudeModel,
      claudeEffort: claudeEffort ?? this.claudeEffort,
      codexModel: codexModel ?? this.codexModel,
      codexEffort: codexEffort ?? this.codexEffort,
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
      other.fixturesDir == fixturesDir &&
      _sameMap(other.stationPositions, stationPositions) &&
      _sameList(other.recentFolders, recentFolders) &&
      other.claudeModel == claudeModel &&
      other.claudeEffort == claudeEffort &&
      other.codexModel == codexModel &&
      other.codexEffort == codexEffort;

  @override
  int get hashCode => Object.hash(
    cwd,
    claudeExecutable,
    codexExecutable,
    permissionMode,
    fake,
    brainFile,
    fixturesDir,
    Object.hashAllUnordered([
      for (final e in stationPositions.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAll(recentFolders),
    claudeModel,
    claudeEffort,
    codexModel,
    codexEffort,
  );

  static bool _sameMap(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'OfficeSettings(${jsonEncode(toJson())})';
}
