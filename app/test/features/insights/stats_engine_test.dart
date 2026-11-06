import 'dart:math';

import 'package:chapter/features/goals/domain/goal.dart';
import 'package:chapter/features/insights/domain/stats_engine.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/progress/domain/progress_event.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:chapter/features/reading/domain/reading_session.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryEntry entry(
  String id, {
  int? pages = 400,
  List<String> authors = const ['Ann'],
  List<String> genres = const ['Romance'],
}) => LibraryEntry(
  workId: id,
  status: ReadingStatus.read,
  addedAt: DateTime.utc(2026),
  book: BookSummary(title: id, pageCount: pages, authorNames: authors, genres: genres),
);

ReadThrough finished(String id, String work, DateTime at) => ReadThrough(
  id: id,
  workId: work,
  ordinal: 1,
  outcome: ReadThroughOutcome.finished,
  finishedAt: at,
);

ReadingSession session(String id, String day, int sec, {int? pages, String work = 'w'}) =>
    ReadingSession(
      id: id,
      workId: work,
      readThroughId: 'r',
      startedAt: DateTime.parse('${day}T10:00:00Z'),
      endedAt: DateTime.parse('${day}T11:00:00Z'),
      plannedDurationSec: sec,
      activeDurationSec: sec,
      localDate: day,
      tzOffsetMin: 0,
      completion: SessionCompletion.completed,
      pagesRead: pages,
    );

ProgressEvent event(
  String id,
  String through,
  DateTime at,
  double fraction, {
  String work = 'w',
  String? edition,
  ReadingPosition position = const ReadingPosition.percent(percent: 1),
  ProgressSource source = ProgressSource.manual,
  String? sessionId,
}) => ProgressEvent(
  id: id,
  workId: work,
  readThroughId: through,
  editionId: edition,
  position: position,
  fraction: fraction,
  isApproximate: false,
  source: source,
  sessionId: sessionId,
  recordedAt: at,
);

/// UTC as the reader's zone, so tests don't depend on the machine's.
StatsEngine engine(StatsInput input, {Duration offset = Duration.zero}) =>
    StatsEngine(input, toLocal: (t) => t.toUtc().add(offset));

void main() {
  const today = '2026-11-05';

  group('empty', () {
    final s = engine(const StatsInput());

    test('everything is zero or not-enough-data, never NaN', () {
      expect(s.totals().isEmpty, isTrue);
      expect(s.averageSession(), isNull);
      expect(s.pagesPerHour(), isNull);
      expect(s.booksPerMonth(today), isNull);
      expect(s.hasTrend(2026), isFalse);
      expect(s.weekdaySeconds(), isNull);
      expect(s.topAuthors(), isNull);
      expect(s.topGenres(), isNull);
      final st = s.streaks(today);
      expect([st.current, st.longest, st.readingDays], [0, 0, 0]);
      expect(s.day(today).isActive, isFalse);
      expect(s.monthly(2026), hasLength(12));
    });
  });

  group('thresholds (sparse data)', () {
    test('one session gives totals but no average or pace', () {
      final s = engine(StatsInput(sessions: [session('a', today, 3000, pages: 90)]));
      expect(s.totals().seconds, 3000);
      expect(s.totals().sessions, 1);
      expect(s.averageSession(), isNull);
      expect(s.pagesPerHour(), isNull);
    });

    test('average appears at three sessions', () {
      final s = engine(
        StatsInput(
          sessions: [
            session('a', today, 600),
            session('b', today, 1200),
            session('c', today, 1800),
          ],
        ),
      );
      expect(s.averageSession(), const Duration(minutes: 20));
    });

    test('pace needs three sessions with pages and an hour of reading', () {
      final short = engine(
        StatsInput(
          sessions: [
            session('a', today, 60, pages: 50),
            session('b', today, 60, pages: 50),
            session('c', today, 60, pages: 50),
          ],
        ),
      );
      expect(short.pagesPerHour(), isNull, reason: '3 minutes would claim 3000 pages/hour');

      final enough = engine(
        StatsInput(
          sessions: [
            session('a', today, 1800, pages: 30),
            session('b', today, 1800, pages: 30),
            session('c', today, 1800, pages: 30),
            session('d', today, 1800), // no pages recorded: not part of pace
          ],
        ),
      );
      expect(enough.pagesPerHour(), closeTo(60, 1e-9));
    });

    test('books per month needs three books over three months', () {
      final input = StatsInput(
        readThroughs: [
          finished('1', 'w', DateTime.utc(2026, 11, 4)),
          finished('2', 'w', DateTime.utc(2026, 11, 2)),
          finished('3', 'w', DateTime.utc(2026, 11, 3)),
        ],
      );
      expect(engine(input).booksPerMonth(today), isNull, reason: 'one month is not a rate');
      expect(engine(input).booksPerMonth('2027-01-15'), closeTo(1, 1e-9));
    });

    test('a single active month is not a trend', () {
      final s = engine(StatsInput(sessions: [session('a', '2026-03-01', 600)]));
      expect(s.hasTrend(2026), isFalse);
      final two = engine(
        StatsInput(sessions: [session('a', '2026-03-01', 600), session('b', '2026-04-01', 600)]),
      );
      expect(two.hasTrend(2026), isTrue);
      expect(two.monthly(2026)[2].seconds, 600);
    });

    test('weekdays need seven sessions; Monday is index 0', () {
      final six = [for (var i = 0; i < 6; i++) session('$i', '2026-11-02', 60)];
      expect(engine(StatsInput(sessions: six)).weekdaySeconds(), isNull);
      final s = engine(StatsInput(sessions: [...six, session('7', '2026-11-08', 120)]));
      expect(s.weekdaySeconds(), [360, 0, 0, 0, 0, 0, 120]);
    });

    test('rankings need three finished books', () {
      final s = engine(
        StatsInput(
          entries: [
            entry('x', authors: ['Ann', 'Bo']),
            entry('y', authors: ['Bo']),
            entry('z', authors: ['Cy'], genres: const []),
          ],
          readThroughs: [
            finished('1', 'x', DateTime.utc(2026)),
            finished('2', 'y', DateTime.utc(2026)),
          ],
        ),
      );
      expect(s.topAuthors(), isNull);
      final t = engine(
        StatsInput(
          entries: s.input.entries,
          readThroughs: [...s.input.readThroughs, finished('3', 'z', DateTime.utc(2026))],
        ),
      );
      expect(t.topAuthors()!.map((r) => r.name), ['Bo', 'Ann', 'Cy']);
      expect(t.topAuthors()!.first.count, 2);
      expect(t.topGenres()!.single.count, 2);
    });
  });

  group('pages', () {
    final d1 = DateTime.utc(2026, 11, 1, 12);
    final d2 = DateTime.utc(2026, 11, 2, 12);
    final d3 = DateTime.utc(2026, 11, 3, 12);

    test('forward movement times page count, by day', () {
      final s = engine(
        StatsInput(
          entries: [entry('w')],
          events: [event('a', 'r', d1, 0.25), event('b', 'r', d2, 0.5)],
        ),
      );
      expect(s.day('2026-11-01').pages, 100);
      expect(s.day('2026-11-02').pages, 100);
      expect(s.totals().pages, 200);
    });

    test('going back then forward is not counted twice', () {
      final s = engine(
        StatsInput(
          entries: [entry('w')],
          events: [event('a', 'r', d1, 0.5), event('b', 'r', d2, 0.25), event('c', 'r', d3, 0.6)],
        ),
      );
      expect(s.totals().pages, 240);
      expect(s.day('2026-11-02').pages, 0);
      expect(s.day('2026-11-03').pages, 40);
    });

    test('a reread counts again, as its own read-through', () {
      final s = engine(
        StatsInput(
          entries: [entry('w')],
          events: [event('a', 'r1', d1, 1), event('b', 'r2', d2, 0.5)],
        ),
      );
      expect(s.totals().pages, 600);
    });

    test('the edition read sets the page count, with overrides', () {
      final s = engine(
        StatsInput(
          entries: [entry('w')],
          editions: const [
            UserEdition(
              editionId: 'e',
              workId: 'w',
              format: 'paperback',
              pageCount: 200,
              pageCountOverride: 100,
            ),
          ],
          events: [event('a', 'r', d1, 0.5, edition: 'e')],
        ),
      );
      expect(s.totals().pages, 50);
    });

    test('an imported dated read counts its pages', () {
      final s = engine(
        StatsInput(
          entries: [entry('w')],
          events: [event('a', 'r', d1, 1, source: ProgressSource.import)],
        ),
      );
      expect(s.day('2026-11-01').pages, 400);
    });

    test('audio and unknown length contribute no pages', () {
      final s = engine(
        StatsInput(
          entries: [entry('w'), entry('n', pages: null)],
          editions: const [UserEdition(editionId: 'au', workId: 'w', format: 'audiobook')],
          events: [
            event('a', 'r1', d1, 0.5, edition: 'au'),
            event('b', 'r2', d1, 0.5, position: const ReadingPosition.audio(seconds: 10)),
            event('c', 'r3', d1, 0.5, work: 'n'),
          ],
        ),
      );
      expect(s.totals().pages, 0);
    });

    test('sessions are not double counted with their progress event', () {
      final s = engine(
        StatsInput(
          entries: [entry('w')],
          sessions: [session('s1', '2026-11-01', 1800, pages: 100)],
          events: [event('a', 'r', d1, 0.25, sessionId: 's1')],
        ),
      );
      expect(s.totals().pages, 100);
      expect(s.totals().seconds, 1800);
    });
  });

  group('finish dates', () {
    ReadThrough through(String id, DateTime? at) => ReadThrough(
      id: id,
      workId: 'w',
      ordinal: 1,
      outcome: ReadThroughOutcome.finished,
      finishedAt: at,
    );
    final (start, end) = Goal.yearRange(2026);
    final goal = Goal(
      id: 'g',
      metric: GoalMetric.books,
      period: GoalPeriod.year,
      start: start,
      end: end,
      target: 10,
    );

    test('an old book counts in its own year, not this one', () {
      final s = engine(StatsInput(readThroughs: [through('a', DateTime.utc(2019, 3, 4, 12))]));
      expect(s.goalProgress(goal).value, 0);
      expect(s.totals(from: '2019-01-01', to: '2019-12-31').books, 1);
    });

    test('a book with no date counts nowhere', () {
      final s = engine(StatsInput(readThroughs: [through('a', null)]));
      expect(s.totals().books, 0);
      expect(s.goalProgress(goal).value, 0);
      expect(s.activeDays, isEmpty);
      expect(s.streaks(today).readingDays, 0);
    });
  });

  group('deleted sessions', () {
    test('disappear from time and pages', () {
      final s = engine(
        StatsInput(
          entries: [entry('w')],
          sessions: [session('s1', today, 1800), session('s2', today, 600)],
          events: [event('a', 'r', DateTime.utc(2026, 11, 5), 0.25, sessionId: 's1')],
          deletedSessionIds: const {'s1'},
        ),
      );
      expect(s.totals().seconds, 600);
      expect(s.totals().sessions, 1);
      expect(s.totals().pages, 0);
    });
  });

  group('days and time zones', () {
    test('events bucket on the reader\'s calendar, not UTC', () {
      final input = StatsInput(
        entries: [entry('w')],
        readThroughs: [finished('1', 'w', DateTime.utc(2026, 11, 1, 23, 30))],
        events: [event('a', 'r', DateTime.utc(2026, 11, 1, 23, 30), 0.25)],
      );
      final utc = engine(input);
      expect(utc.day('2026-11-01').books, 1);
      final india = engine(input, offset: const Duration(hours: 5, minutes: 30));
      expect(india.day('2026-11-02').books, 1);
      expect(india.day('2026-11-02').pages, 100);
      expect(india.day('2026-11-01').isActive, isFalse);
      final la = engine(input, offset: const Duration(hours: -8));
      expect(la.day('2026-11-01').books, 1);
    });

    test('a session stays on its stored local date whatever the zone is later', () {
      final input = StatsInput(sessions: [session('a', '2026-11-01', 600)]);
      final tokyo = engine(input, offset: const Duration(hours: 9));
      expect(tokyo.day('2026-11-01').seconds, 600);
    });

    test('streak survives a daylight-saving change', () {
      // US clocks went back on 2026-11-01.
      final s = engine(
        StatsInput(
          sessions: [
            session('a', '2026-10-31', 600),
            session('b', '2026-11-01', 600),
            session('c', '2026-11-02', 600),
          ],
        ),
      );
      expect(s.streaks('2026-11-02').current, 3);
    });
  });

  group('streaks', () {
    final s = engine(
      StatsInput(
        sessions: [
          session('a', '2026-10-01', 60),
          session('b', '2026-10-02', 60),
          session('c', '2026-10-03', 60),
          session('d', '2026-10-04', 60),
          session('e', '2026-11-03', 60),
          session('f', '2026-11-04', 60),
        ],
      ),
    );

    test('today not read yet doesn\'t break the current run', () {
      expect(s.streaks('2026-11-05').current, 2);
      expect(s.streaks('2026-11-04').current, 2);
    });

    test('a missed full day ends the current run but not the longest', () {
      final st = s.streaks('2026-11-06');
      expect(st.current, 0);
      expect(st.longest, 4);
      expect(st.readingDays, 6);
    });

    test('future-dated activity is ignored', () {
      expect(s.streaks('2026-10-02').readingDays, 2);
    });
  });

  group('goals', () {
    final input = StatsInput(
      entries: [entry('w')],
      readThroughs: [
        finished('in', 'w', DateTime.utc(2026, 6, 2)),
        finished('out', 'w', DateTime.utc(2025, 12, 31)),
      ],
      sessions: [session('a', '2026-01-01', 3600), session('b', '2026-12-31', 1800)],
      events: [event('e', 'r', DateTime.utc(2026, 3, 2), 0.5)],
    );
    final (start, end) = Goal.yearRange(2026);
    Goal g(GoalMetric m, int target) =>
        Goal(id: 'g', metric: m, period: GoalPeriod.year, start: start, end: end, target: target);

    test('match the underlying data; range is inclusive', () {
      final s = engine(input);
      expect(s.goalProgress(g(GoalMetric.books, 2)).value, 1);
      expect(s.goalProgress(g(GoalMetric.minutes, 100)).value, 90);
      expect(s.goalProgress(g(GoalMetric.pages, 100)).value, 200);
    });

    test('exceeding the target keeps the real value, fraction stays at 1', () {
      final p = engine(input).goalProgress(g(GoalMetric.pages, 100));
      expect(p.value, 200);
      expect(p.fraction, 1);
      expect(p.isMet, isTrue);
    });

    test('a zero target can\'t divide by zero', () {
      final p = engine(input).goalProgress(g(GoalMetric.pages, 0));
      expect(p.fraction, 0);
      expect(p.isMet, isFalse);
    });

    test('month range handles February and leap years', () {
      expect(Goal.monthRange(2026, 2), ('2026-02-01', '2026-02-28'));
      expect(Goal.monthRange(2028, 2), ('2028-02-01', '2028-02-29'));
      expect(Goal.monthRange(2026, 12), ('2026-12-01', '2026-12-31'));
    });
  });

  group('dense and hostile data (randomized)', () {
    void checkSane(StatsEngine s) {
      void num0(num? v) {
        if (v == null) return;
        expect(v.isFinite, isTrue);
        expect(v, greaterThanOrEqualTo(0));
      }

      final t = s.totals();
      [t.books, t.pages, t.seconds, t.sessions].forEach(num0);
      num0(s.averageSession()?.inSeconds);
      num0(s.pagesPerHour());
      num0(s.booksPerMonth('2030-01-01'));
      s.weekdaySeconds()?.forEach(num0);
      for (final y in [2024, 2025, 2026]) {
        for (final p in s.monthly(y)) {
          [p.books, p.pages, p.seconds].forEach(num0);
        }
      }
      final st = s.streaks('2030-01-01');
      expect(st.longest, greaterThanOrEqualTo(st.current));
      expect(st.longest, lessThanOrEqualTo(st.readingDays));
    }

    for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('seed $seed', () {
        final r = Random(seed);
        DateTime when() => DateTime.utc(2024 + r.nextInt(3), 1 + r.nextInt(12), 1 + r.nextInt(28));
        String date(DateTime d) => d.toIso8601String().substring(0, 10);
        final hostile = [double.nan, double.infinity, -1.0, 2.0, 0.0, 1.0];
        final input = StatsInput(
          entries: [
            for (var i = 0; i < 20; i++)
              entry(
                'w$i',
                pages: r.nextBool() ? null : r.nextInt(1000),
                authors: ['A${r.nextInt(5)}'],
              ),
          ],
          readThroughs: [
            for (var i = 0; i < 200; i++)
              ReadThrough(
                id: 'rt${r.nextInt(150)}', // duplicates on purpose
                workId: 'w${r.nextInt(25)}', // some unknown works
                ordinal: 1,
                outcome: ReadThroughOutcome.values[r.nextInt(3)],
                finishedAt: r.nextBool() ? when() : null,
              ),
          ],
          sessions: [
            for (var i = 0; i < 500; i++)
              session(
                's$i',
                date(when()),
                r.nextInt(7200) - 100, // some negative
                pages: r.nextBool() ? r.nextInt(100) : null,
              ),
          ],
          events: [
            for (var i = 0; i < 1000; i++)
              event(
                'e$i',
                'rt${r.nextInt(50)}',
                when(),
                r.nextInt(5) == 0 ? hostile[r.nextInt(hostile.length)] : r.nextDouble(),
                work: 'w${r.nextInt(25)}',
              ),
          ],
        );
        checkSane(engine(input));
      });
    }
  });
}
