import 'package:agent_office_app/desktop/desktop_stage.dart';
import 'package:agent_office_app/l10n_tr.dart';
import 'package:agent_office_app/state/office_controller.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

Map<String, Object?> rateLimitRaw(
  String window, {
  String status = 'allowed',
  double? utilization,
  int resetsAt = 1793372400,
}) => {
  'type': 'rate_limit_event',
  'rate_limit_info': {
    'status': status,
    'rateLimitType': window,
    'utilization': ?utilization,
    'resetsAt': resetsAt,
  },
};

void main() {
  final fetched = DateTime.utc(2026, 10, 29, 12);

  group('usageFromRateLimit', () {
    test('utilization becomes a percentage', () {
      final u = usageFromRateLimit(
        Seat.claude,
        rateLimitRaw('five_hour', utilization: 0.42),
        fetched,
      )!;
      expect(u.window, 'five_hour');
      expect(u.usedPct, closeTo(42, 0.001));
      expect(u.resetsAt, DateTime.utc(2026, 10, 30, 15));
    });

    test('no utilization (below the warning line) is unknown, not 0 %', () {
      final u = usageFromRateLimit(
        Seat.claude,
        rateLimitRaw('five_hour'),
        fetched,
      )!;
      expect(u.usedPct, usageUnknown);
    });

    test('a line without rate_limit_info gives nothing', () {
      expect(usageFromRateLimit(Seat.claude, const {}, fetched), isNull);
    });
  });

  test('usageFromEvents keeps the newest event per seat and window', () {
    BoardEvent event(int id, Map<String, Object?> raw, DateTime at) =>
        BoardEvent(
          id: id,
          seat: 'claude',
          kind: 'rateLimit',
          summary: 'rate limit',
          raw: raw,
          createdAt: at,
        );
    // listEvents returns newest first.
    final usage = usageFromEvents([
      event(3, rateLimitRaw('seven_day', utilization: 0.86), fetched),
      event(2, rateLimitRaw('five_hour', utilization: 0.5), fetched),
      event(1, rateLimitRaw('five_hour', utilization: 0.1), fetched),
    ]);
    expect(usage, hasLength(2));
    final five = usage.firstWhere((u) => u.window == 'five_hour');
    expect(five.usedPct, closeTo(50, 0.001));
  });

  group('usageBars', () {
    final now = DateTime(2026, 10, 29, 12);
    OfficeSnapshot withUsage(List<UsageSnapshot> usage) =>
        OfficeSnapshot(seats: OfficeSnapshot.initial().seats, usage: usage);
    UsageSnapshot usage(double pct, DateTime? resetsAt) => UsageSnapshot(
      seat: Seat.claude,
      window: 'five_hour',
      usedPct: pct,
      resetsAt: resetsAt,
      source: 'claude-cli',
      fetchedAt: now,
    );

    test('a known value keeps its percentage and reset time', () {
      final bar = DesktopStage.usageBars(
        withUsage([usage(42, now.add(const Duration(hours: 2)))]),
        now: now,
      ).single;
      expect(bar.known, isTrue);
      expect(bar.pct, closeTo(0.42, 0.001));
      expect(DesktopStage.captionLine(bar, now: now), contains('%42'));
      expect(DesktopStage.captionLine(bar, now: now), contains('14:00'));
    });

    test('an unknown value reads "sorun yok", never %0', () {
      final bar = DesktopStage.usageBars(
        withUsage([usage(usageUnknown, now.add(const Duration(hours: 2)))]),
        now: now,
      ).single;
      expect(bar.known, isFalse);
      final line = DesktopStage.captionLine(bar, now: now);
      expect(line, contains(Tr.usageOk));
      expect(line, isNot(contains('%')));
    });

    test('a window whose reset time passed reads "yenilendi"', () {
      final bar = DesktopStage.usageBars(
        withUsage([usage(86, now.subtract(const Duration(hours: 1)))]),
        now: now,
      ).single;
      expect(bar.known, isFalse);
      expect(
        DesktopStage.captionLine(bar, now: now),
        contains(Tr.usageRenewed),
      );
    });
  });
}
