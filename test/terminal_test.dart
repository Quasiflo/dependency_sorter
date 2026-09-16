import 'package:dependency_sorter/dependency_sorter.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalStyle', () {
    test('wraps text in ANSI codes when enabled', () {
      const TerminalStyle style = TerminalStyle(enabled: true);
      expect(style.green('ok'), '\x1b[32mok\x1b[0m');
      expect(style.red('err'), '\x1b[31merr\x1b[0m');
      expect(style.yellow('warn'), '\x1b[33mwarn\x1b[0m');
      expect(style.cyan('hunk'), '\x1b[36mhunk\x1b[0m');
      expect(style.bold('title'), '\x1b[1mtitle\x1b[0m');
      expect(style.dim('detail'), '\x1b[2mdetail\x1b[0m');
    });

    test('returns text unchanged when disabled', () {
      const TerminalStyle style = TerminalStyle(enabled: false);
      expect(style.green('ok'), 'ok');
      expect(style.red('err'), 'err');
      expect(style.yellow('warn'), 'warn');
      expect(style.cyan('hunk'), 'hunk');
      expect(style.bold('title'), 'title');
      expect(style.dim('detail'), 'detail');
    });

    test('exposes status marks', () {
      expect(TerminalStyle.okMark, isNotEmpty);
      expect(TerminalStyle.failMark, isNotEmpty);
      expect(TerminalStyle.okMark, isNot(TerminalStyle.failMark));
    });
  });
}
