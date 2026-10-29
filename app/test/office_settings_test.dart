import 'package:agent_office_app/desktop/model_choices.dart';
import 'package:agent_office_app/runtime/office_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

void main() {
  test('model and effort per seat survive a JSON round trip', () {
    const settings = OfficeSettings(
      cwd: r'C:\work\repo',
      claudeModel: 'sonnet',
      claudeEffort: 'high',
      codexModel: 'gpt-5.1',
      codexEffort: 'low',
    );
    final back = OfficeSettings.fromJson(settings.toJson());
    expect(back, settings);
    expect(back.claudeModel, 'sonnet');
    expect(back.codexEffort, 'low');
  });

  test('a settings file without the new keys keeps the CLI defaults', () {
    final loaded = OfficeSettings.fromJson({'cwd': r'C:\work\repo'});
    expect(loaded.claudeModel, '');
    expect(loaded.claudeEffort, '');
    expect(loaded.codexModel, '');
    expect(loaded.codexEffort, '');
  });

  test('defaultOptions picks the seat\'s model and effort', () {
    const settings = OfficeSettings(
      cwd: r'C:\work\repo',
      claudeModel: 'opus',
      claudeEffort: 'max',
      codexModel: 'gpt-5.1-codex',
    );
    expect(
      settings.defaultOptions(Seat.claude),
      const PromptOptions(model: 'opus', effort: 'max'),
    );
    expect(
      settings.defaultOptions(Seat.gpt),
      const PromptOptions(model: 'gpt-5.1-codex'),
    );
  });

  test('the TV keeps the coffee machine\'s old position', () {
    final loaded = OfficeSettings.fromJson({
      'cwd': r'C:\work\repo',
      'stationPositions': {'coffee': 0.5, 'mailbox': 0.9},
    });
    expect(loaded.stationPositions['tv'], 0.5);
    expect(loaded.stationPositions.containsKey('coffee'), isFalse);
  });
}
