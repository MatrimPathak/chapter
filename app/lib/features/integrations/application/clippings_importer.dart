import 'package:meta/meta.dart';

import '../../library/domain/library_models.dart';
import '../../notes/data/lww_notes_repository.dart';
import '../../notes/domain/note.dart';
import '../domain/kindle_clippings.dart';

@immutable
class ClippingsPlan {
  const ClippingsPlan({required this.matched, required this.unmatched, required this.skipped});

  /// Clippings and the library book each belongs to.
  final List<({Clipping clip, String workId})> matched;

  /// Titles not in the library, with how many clippings each has.
  final Map<String, int> unmatched;

  /// Entries the parser couldn't read.
  final int skipped;
}

/// Pairs clippings with library books, without changing anything.
ClippingsPlan planClippings(ClippingsFile file, List<LibraryEntry> entries) {
  final library = [
    for (final e in entries) (workId: e.workId, title: e.book.title, authors: e.book.authorNames),
  ];
  final matched = <({Clipping clip, String workId})>[];
  final unmatched = <String, int>{};
  for (final clip in file.clippings) {
    final workId = matchLibraryBook(clip, library);
    if (workId == null) {
      unmatched[clip.title] = (unmatched[clip.title] ?? 0) + 1;
    } else {
      matched.add((clip: clip, workId: workId));
    }
  }
  return ClippingsPlan(matched: matched, unmatched: unmatched, skipped: file.skipped);
}

/// Saves the matched clippings as notes. Returns how many were new: seen ones
/// are left exactly as they are, even if edited or deleted since.
Future<int> importClippings(ClippingsPlan plan, LwwNotesRepository notes) async {
  var added = 0;
  for (final m in plan.matched) {
    final isNew = await notes.importNote(
      id: 'kc_${m.clip.key}',
      workId: m.workId,
      text: m.clip.text,
      kind: m.clip.kind == ClippingKind.highlight ? NoteKind.quote : NoteKind.note,
      page: m.clip.page,
      location: m.clip.location,
    );
    if (isNew) added++;
  }
  return added;
}
