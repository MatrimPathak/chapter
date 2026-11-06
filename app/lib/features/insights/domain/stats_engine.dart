import 'package:meta/meta.dart';

import '../../goals/domain/goal.dart';
import '../../library/domain/library_models.dart';
import '../../progress/domain/progress_event.dart';
import '../../progress/domain/progress_mapper.dart';
import '../../progress/domain/reading_position.dart';
import '../../reading/domain/reading_session.dart';

/// What statistics are computed from. Everything is derived, never stored.
@immutable
class StatsInput {
  const StatsInput({
    this.entries = const [],
    this.readThroughs = const [],
    this.sessions = const [],
    this.events = const [],
    this.editions = const [],
    this.deletedSessionIds = const {},
  });

  /// Library entries, for page counts, authors and genres.
  final List<LibraryEntry> entries;
  final List<ReadThrough> readThroughs;
  final List<ReadingSession> sessions;
  final List<ProgressEvent> events;
  final List<UserEdition> editions;
  final Set<String> deletedSessionIds;
}

/// Activity on one local day.
@immutable
class DayActivity {
  const DayActivity({this.seconds = 0, this.pages = 0, this.books = 0});

  final int seconds;
  final int pages;
  final int books;

  bool get isActive => seconds > 0 || pages > 0 || books > 0;
}

@immutable
class Totals {
  const Totals({this.books = 0, this.pages = 0, this.seconds = 0, this.sessions = 0});

  final int books;
  final int pages;
  final int seconds;
  final int sessions;

  int get minutes => seconds ~/ 60;
  bool get isEmpty => books == 0 && pages == 0 && seconds == 0;
}

@immutable
class MonthPoint {
  const MonthPoint({
    required this.month,
    required this.books,
    required this.pages,
    required this.seconds,
  });

  /// 1–12.
  final int month;
  final int books;
  final int pages;
  final int seconds;
}

@immutable
class RankedName {
  const RankedName(this.name, this.count);

  final String name;
  final int count;
}

@immutable
class Streaks {
  const Streaks({required this.current, required this.longest, required this.readingDays});

  /// Consecutive reading days ending today or yesterday (a day isn't lost
  /// until it is over).
  final int current;
  final int longest;
  final int readingDays;
}

@immutable
class GoalProgress {
  const GoalProgress({required this.value, required this.target});

  final int value;
  final int target;

  /// 0–1 for display; [value] itself may exceed [target].
  double get fraction => target <= 0 ? 0 : (value / target).clamp(0.0, 1.0);
  bool get isMet => target > 0 && value >= target;
}

/// Reading statistics (docs/03 §6). Pure, deterministic and honest: each
/// statistic that could mislead on little data returns `null` below its
/// threshold, and the engine never produces NaN, Infinity or negative values.
///
/// Definitions:
/// - **Books:** finished read-throughs on their finish date. A reread counts
///   again; a book marked as read without a date doesn't count.
/// - **Time:** active session time, on the session's stored local date (so a
///   later time-zone change doesn't move it).
/// - **Pages:** forward movement in the progress log, per read-through, from
///   its high-water mark, times the page count of the edition read. Going
///   back and re-reading isn't counted twice. Audio and books of unknown
///   length contribute no pages.
class StatsEngine {
  StatsEngine(this.input, {DateTime Function(DateTime)? toLocal})
    : _toLocal = toLocal ?? ((t) => t.toLocal()) {
    _build();
  }

  final StatsInput input;
  final DateTime Function(DateTime) _toLocal;

  static const minSessionsForAverage = 3;
  static const minSessionsForPace = 3;
  static const minSecondsForPace = 3600;
  static const minBooksForRanking = 3;
  static const minSessionsForWeekdays = 7;
  static const minBooksForMonthlyRate = 3;
  static const minMonthsForMonthlyRate = 3;
  static const minActiveMonthsForTrend = 2;
  static const minDaysForLongestStreak = 3;

  final Map<String, _Day> _days = {};
  final List<ReadingSession> _sessions = [];
  final List<_Finish> _finishes = [];

  /// `YYYY-MM-DD` of [t] on the reader's calendar.
  String dayOf(DateTime t) {
    final l = _toLocal(t);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}';
  }

  void _build() {
    for (final s in input.sessions) {
      if (input.deletedSessionIds.contains(s.id) || s.activeDurationSec <= 0) continue;
      _sessions.add(s);
      _days.putIfAbsent(s.localDate, _Day.new).seconds += s.activeDurationSec;
    }

    final seen = <String>{};
    final books = {for (final e in input.entries) e.workId: e};
    for (final rt in input.readThroughs) {
      final at = rt.finishedAt;
      if (rt.outcome != ReadThroughOutcome.finished || at == null || !seen.add(rt.id)) continue;
      final day = dayOf(at);
      _days.putIfAbsent(day, _Day.new).books += 1;
      _finishes.add(_Finish(day, books[rt.workId]));
    }

    _buildPages(books);
  }

  void _buildPages(Map<String, LibraryEntry> books) {
    final editions = {for (final e in input.editions) e.editionId: e};
    final byThrough = <String, List<ProgressEvent>>{};
    final throughs = {for (final t in input.readThroughs) t.id: t};
    for (final e in input.events) {
      if (!e.fraction.isFinite) continue;
      byThrough.putIfAbsent(e.readThroughId, () => []).add(e);
    }
    for (final events in byThrough.values) {
      events.sort(ProgressEvent.compare);
      var high = 0.0;
      for (final e in events) {
        final fraction = e.fraction.clamp(0.0, 1.0);
        final gained = fraction - high;
        if (gained <= 0) continue;
        high = fraction;
        // A deleted session's movement stays spent: the book really is at that
        // page, so later progress must not count those pages again.
        if (e.sessionId != null && input.deletedSessionIds.contains(e.sessionId)) continue;
        // A read marked finished without tracking has one event, stamped when it
        // was marked. Its pages follow the read's date, which can be corrected.
        final through = throughs[e.readThroughId];
        final soleFinish =
            events.length == 1 &&
            e.position is FinishedPosition &&
            through?.outcome == ReadThroughOutcome.finished;
        final at = soleFinish ? through!.finishedAt : e.recordedAt;
        if (at == null) continue; // finish date unknown: counts nowhere (TD-38)
        final pages = _pagesOf(e, editions, books);
        if (pages == null) continue;
        _days.putIfAbsent(dayOf(at), _Day.new).pages += gained * pages;
      }
    }
  }

  int? _pagesOf(
    ProgressEvent e,
    Map<String, UserEdition> editions,
    Map<String, LibraryEntry> books,
  ) {
    if (e.position is AudioPosition) return null;
    final edition = editions[e.editionId];
    if (edition != null) {
      if (mediumOf(edition.format) == MediumKind.audio) return null;
      final pages = edition.effectivePageCount;
      if (pages != null && pages > 0) return pages;
    }
    final pages = books[e.workId]?.book.pageCount;
    return pages != null && pages > 0 ? pages : null;
  }

  bool _inRange(String day, String? from, String? to) =>
      (from == null || day.compareTo(from) >= 0) && (to == null || day.compareTo(to) <= 0);

  /// Activity on one local day.
  DayActivity day(String date) {
    final d = _days[date];
    return d == null
        ? const DayActivity()
        : DayActivity(seconds: d.seconds, pages: d.pages.round(), books: d.books);
  }

  /// Days with any activity, for the calendar.
  Iterable<String> get activeDays => _days.keys;

  /// Totals over inclusive local dates (all time when both are null).
  Totals totals({String? from, String? to}) {
    var books = 0;
    var pages = 0.0;
    var seconds = 0;
    _days.forEach((date, d) {
      if (!_inRange(date, from, to)) return;
      books += d.books;
      pages += d.pages;
      seconds += d.seconds;
    });
    final sessions = _sessions.where((s) => _inRange(s.localDate, from, to)).length;
    return Totals(books: books, pages: pages.round(), seconds: seconds, sessions: sessions);
  }

  /// Average session length, or `null` with fewer than
  /// [minSessionsForAverage] sessions.
  Duration? averageSession({String? from, String? to}) {
    final list = _sessions.where((s) => _inRange(s.localDate, from, to)).toList();
    if (list.length < minSessionsForAverage) return null;
    final total = list.fold(0, (sum, s) => sum + s.activeDurationSec);
    return Duration(seconds: total ~/ list.length);
  }

  /// Pages per hour across sessions that recorded pages, or `null` with too
  /// few sessions or too little time for the number to mean anything.
  double? pagesPerHour({String? from, String? to}) {
    final list = _sessions
        .where((s) => s.pagesRead != null && _inRange(s.localDate, from, to))
        .toList();
    if (list.length < minSessionsForPace) return null;
    final seconds = list.fold(0, (sum, s) => sum + s.activeDurationSec);
    if (seconds < minSecondsForPace) return null;
    final pages = list.fold(0, (sum, s) => sum + (s.pagesRead ?? 0));
    return pages * 3600 / seconds;
  }

  /// Books finished per month from the first finish to [today], or `null`
  /// with too few books or too short a span.
  double? booksPerMonth(String today) {
    final dates = _finishes.map((f) => f.day).where((d) => d.compareTo(today) <= 0).toList()
      ..sort();
    if (dates.length < minBooksForMonthlyRate) return null;
    final months = _monthsBetween(dates.first, today);
    if (months < minMonthsForMonthlyRate) return null;
    return dates.length / months;
  }

  /// Calendar months touched from [from] to [to], inclusive.
  static int _monthsBetween(String from, String to) {
    int index(String d) => int.parse(d.substring(0, 4)) * 12 + int.parse(d.substring(5, 7));
    return index(to) - index(from) + 1;
  }

  /// Twelve points for [year]. Check [hasTrend] before drawing it as a trend.
  List<MonthPoint> monthly(int year) {
    final books = List<int>.filled(12, 0);
    final pages = List<double>.filled(12, 0);
    final seconds = List<int>.filled(12, 0);
    final prefix = '$year-';
    _days.forEach((date, d) {
      if (!date.startsWith(prefix)) return;
      final m = int.parse(date.substring(5, 7)) - 1;
      books[m] += d.books;
      pages[m] += d.pages;
      seconds[m] += d.seconds;
    });
    return [
      for (var m = 0; m < 12; m++)
        MonthPoint(month: m + 1, books: books[m], pages: pages[m].round(), seconds: seconds[m]),
    ];
  }

  /// A single active month isn't a trend.
  bool hasTrend(int year) =>
      monthly(year).where((p) => p.books > 0 || p.pages > 0 || p.seconds > 0).length >=
      minActiveMonthsForTrend;

  /// Reading seconds per weekday, Monday first (index 0), or `null` with fewer
  /// than [minSessionsForWeekdays] sessions.
  List<int>? weekdaySeconds({String? from, String? to}) {
    final list = _sessions.where((s) => _inRange(s.localDate, from, to)).toList();
    if (list.length < minSessionsForWeekdays) return null;
    final out = List<int>.filled(7, 0);
    for (final s in list) {
      final d = _parse(s.localDate);
      if (d != null) out[d.weekday - 1] += s.activeDurationSec;
    }
    return out;
  }

  /// Most-finished authors, or `null` with fewer than [minBooksForRanking]
  /// finished books whose details are known.
  List<RankedName>? topAuthors({String? from, String? to, int limit = 5}) =>
      _rank(from, to, limit, (b) => b.authorNames);

  List<RankedName>? topGenres({String? from, String? to, int limit = 5}) =>
      _rank(from, to, limit, (b) => b.genres);

  List<RankedName>? _rank(
    String? from,
    String? to,
    int limit,
    List<String> Function(BookSummary) namesOf,
  ) {
    final finishes = _finishes.where((f) => f.entry != null && _inRange(f.day, from, to)).toList();
    if (finishes.length < minBooksForRanking) return null;
    final counts = <String, int>{};
    for (final f in finishes) {
      for (final name in namesOf(f.entry!.book).toSet()) {
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    final ranked = [for (final e in counts.entries) RankedName(e.key, e.value)]
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.name.compareTo(b.name);
      });
    return ranked.take(limit).toList();
  }

  /// Consecutive reading days. Day arithmetic is done in UTC on calendar dates,
  /// so daylight-saving changes can't break a run.
  Streaks streaks(String today) {
    final now = _parse(today);
    final days = <DateTime>{};
    _days.forEach((date, d) {
      final parsed = d.isActive ? _parse(date) : null;
      if (parsed != null && (now == null || !parsed.isAfter(now))) days.add(parsed);
    });
    if (days.isEmpty || now == null) {
      return Streaks(current: 0, longest: 0, readingDays: days.length);
    }
    var longest = 0;
    for (final d in days) {
      if (days.contains(d.subtract(const Duration(days: 1)))) continue; // not a run's start
      var length = 1;
      var next = d.add(const Duration(days: 1));
      while (days.contains(next)) {
        length++;
        next = next.add(const Duration(days: 1));
      }
      if (length > longest) longest = length;
    }
    var cursor = days.contains(now) ? now : now.subtract(const Duration(days: 1));
    var current = 0;
    while (days.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return Streaks(current: current, longest: longest, readingDays: days.length);
  }

  /// A goal's progress, from the same data as everything else.
  GoalProgress goalProgress(Goal goal) {
    final t = totals(from: goal.start, to: goal.end);
    final value = switch (goal.metric) {
      GoalMetric.books => t.books,
      GoalMetric.pages => t.pages,
      GoalMetric.minutes => t.minutes,
    };
    return GoalProgress(value: value, target: goal.target);
  }

  static DateTime? _parse(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    return y == null || m == null || d == null ? null : DateTime.utc(y, m, d);
  }
}

class _Day {
  int seconds = 0;
  double pages = 0;
  int books = 0;

  bool get isActive => seconds > 0 || pages > 0 || books > 0;
}

class _Finish {
  const _Finish(this.day, this.entry);

  final String day;
  final LibraryEntry? entry;
}
