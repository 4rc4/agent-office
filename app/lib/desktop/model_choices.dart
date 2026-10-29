import 'package:flutter/foundation.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';

/// The fixed menus behind the model and effort chips of the prompt bubble
/// and the settings sheet. An empty choice means the CLI's own default.
abstract final class ModelChoices {
  static const List<String> claudeModels = ['opus', 'sonnet', 'haiku'];
  static const List<String> claudeEfforts = ['low', 'medium', 'high', 'max'];
  static const List<String> codexModels = [
    'gpt-5.1-codex',
    'gpt-5.1',
    'gpt-5-codex-mini',
  ];
  static const List<String> codexEfforts = ['low', 'medium', 'high'];

  static List<String> modelsFor(Seat seat) =>
      seat == Seat.gpt ? codexModels : claudeModels;

  static List<String> effortsFor(Seat seat) =>
      seat == Seat.gpt ? codexEfforts : claudeEfforts;
}

/// What one prompt runs with: the model and the effort (thinking level) the
/// CLI is started with. Empty strings keep the settings' defaults, which in
/// turn may be empty (the CLI decides).
@immutable
class PromptOptions {
  const PromptOptions({this.model = '', this.effort = ''});

  final String model;
  final String effort;

  /// The task options office_core stores on the root: only the set values.
  Map<String, String> toMap() => {
    if (model.isNotEmpty) 'model': model,
    if (effort.isNotEmpty) 'effort': effort,
  };

  PromptOptions copyWith({String? model, String? effort}) =>
      PromptOptions(model: model ?? this.model, effort: effort ?? this.effort);

  @override
  bool operator ==(Object other) =>
      other is PromptOptions && other.model == model && other.effort == effort;

  @override
  int get hashCode => Object.hash(model, effort);

  @override
  String toString() => 'PromptOptions($model, $effort)';
}

/// What goes under a prompt that carries attachments: a heading and one
/// path per line, which the agent reads itself. Empty without attachments.
String attachmentSuffix(List<String> paths) {
  if (paths.isEmpty) return '';
  return '\n\n${Tr.attachedFiles}:\n${paths.map((p) => '- $p').join('\n')}';
}
