import 'package:agent_office_app/desktop/model_choices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

void main() {
  test('PromptOptions.toMap drops empty values', () {
    expect(const PromptOptions().toMap(), isEmpty);
    expect(const PromptOptions(model: 'opus').toMap(), {'model': 'opus'});
    expect(const PromptOptions(model: 'opus', effort: 'high').toMap(), {
      'model': 'opus',
      'effort': 'high',
    });
  });

  test('attachmentSuffix lists one path per line, nothing when empty', () {
    expect(attachmentSuffix(const []), '');
    expect(
      attachmentSuffix(const [r'C:\img\shot.png', r'C:\doc\spec.md']),
      '\n\nEkli dosyalar (yoluyla oku):\n- C:\\img\\shot.png\n- C:\\doc\\spec.md',
    );
  });

  test('every seat has a model and an effort menu', () {
    expect(ModelChoices.modelsFor(Seat.claude), contains('opus'));
    expect(ModelChoices.effortsFor(Seat.claude), contains('max'));
    expect(ModelChoices.modelsFor(Seat.gpt), contains('gpt-5.1-codex'));
    expect(ModelChoices.effortsFor(Seat.gpt), isNot(contains('max')));
  });
}
