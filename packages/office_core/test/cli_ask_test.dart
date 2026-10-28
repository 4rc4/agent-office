import 'package:office_core/src/cli/office_cli.dart';
import 'package:office_core/src/model/task.dart';
import 'package:test/test.dart';

void main() {
  group('ask command', () {
    test('parses seat, prompt and options', () {
      final invocation = parseCliArguments([
        'ask',
        'gpt',
        'Explain this stack trace',
        '--cwd',
        '/repo',
      ]);
      expect(invocation.command, 'ask');
      expect(invocation.seat, Seat.gpt);
      expect(invocation.prompt, 'Explain this stack trace');
      expect(invocation.config.paths.cwd, '/repo');
    });

    test('accepts codex as an alias of gpt and claude as a seat', () {
      expect(parseCliArguments(['ask', 'codex', 'hi']).seat, Seat.gpt);
      expect(parseCliArguments(['ask', 'claude', 'hi']).seat, Seat.claude);
    });

    test('rejects an unknown seat or a missing prompt', () {
      expect(
        () => parseCliArguments(['ask', 'bard', 'hi']),
        throwsFormatException,
      );
      expect(() => parseCliArguments(['ask', 'gpt']), throwsFormatException);
      expect(
        () => parseCliArguments(['ask', 'gpt', '--cwd', '/x']),
        throwsFormatException,
      );
    });
  });
}
