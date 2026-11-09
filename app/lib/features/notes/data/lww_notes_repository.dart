import '../../../core/sync/lww_store.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_remote.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/note.dart';

/// Notes over the local LWW store (`users/{uid}/notes`). Local-first.
///
/// Text is the reader's own writing, so plain last-writer-wins isn't enough:
/// if two devices edit a note without seeing each other's change, the older
/// text is kept as a conflict-copy note. The copy's id comes from the losing
/// version's clock, so any number of devices produce the same single copy.
class LwwNotesRepository {
  LwwNotesRepository({
    required LwwStore store,
    required Clock clock,
    required IdGenerator ids,
    required String uid,
    required void Function() onLocalWrite,
  }) : _store = store,
       _clock = clock,
       _ids = ids,
       _onLocalWrite = onLocalWrite,
       path = 'users/$uid/notes';

  final LwwStore _store;
  final Clock _clock;
  final IdGenerator _ids;
  final void Function() _onLocalWrite;
  final String path;

  /// Every note, newest first.
  Stream<List<Note>> watchAllNotes() => _store.watchCollection(path).map((docs) {
    return [for (final e in docs.entries) ?Note.fromFields(e.key, e.value.fields)]..sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  });

  /// Notes of one book, oldest first.
  Stream<List<Note>> watchNotes(String workId) => _store.watchCollection(path).map((docs) {
    final list =
        [
          for (final e in docs.entries) ?Note.fromFields(e.key, e.value.fields),
        ].where((n) => n.workId == workId).toList()..sort((a, b) {
          final byDate = a.createdAt.compareTo(b.createdAt);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });
    return list;
  });

  /// Returns the new id, or `null` if [text] is empty or too long.
  Future<String?> add({
    required String workId,
    required String text,
    NoteKind kind = NoteKind.note,
    int? page,
  }) async {
    final clean = _clean(text);
    if (clean == null) return null;
    final id = _ids.newId();
    await _store.write('$path/$id', {
      NoteFields.workId: workId,
      NoteFields.kind: kind.name,
      NoteFields.text: clean,
      NoteFields.page: page,
      NoteFields.createdAt: _clock.now().toUtc().toIso8601String(),
    });
    _onLocalWrite();
    return id;
  }

  /// Returns `false` if [text] is empty or too long.
  Future<bool> edit(String id, {required String text, NoteKind? kind, int? page}) async {
    final clean = _clean(text);
    if (clean == null) return false;
    final doc = await _store.read('$path/$id');
    final current = doc.clocks[NoteFields.text];
    final textChanged = doc.fields[NoteFields.text] != clean;
    await _store.write('$path/$id', {
      if (textChanged) ...{
        NoteFields.text: clean,
        NoteFields.textHistory: _extendedHistory(doc.fields[NoteFields.textHistory], current),
        // An edit made after a delete on another device brings the note back.
        NoteFields.deleted: false,
      },
      if (kind != null) NoteFields.kind: kind.name,
      NoteFields.page: page,
    });
    _onLocalWrite();
    return true;
  }

  Future<void> delete(String id) async {
    await _store.write('$path/$id', {NoteFields.deleted: true});
    _onLocalWrite();
  }

  /// Adds a note from an import under a stable [id]. Returns `false` if that id
  /// was seen before: an edited note stays edited and a deleted one stays gone.
  Future<bool> importNote({
    required String id,
    required String workId,
    required String text,
    required NoteKind kind,
    int? page,
    int? location,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    final notePath = '$path/$id';
    if ((await _store.read(notePath)).fields.isNotEmpty) return false;
    await _store.write(notePath, {
      NoteFields.workId: workId,
      NoteFields.kind: kind.name,
      NoteFields.text: clean.length > NoteFields.maxTextLength
          ? clean.substring(0, NoteFields.maxTextLength)
          : clean,
      NoteFields.page: page,
      NoteFields.location: location,
      NoteFields.createdAt: _clock.now().toUtc().toIso8601String(),
    });
    _onLocalWrite();
    return true;
  }

  Future<void> attachSync(SyncEngine engine) => engine.watchCollection(path, applyRemote);

  /// Merges a note pulled from the server, keeping this device's text as a
  /// conflict copy if it is about to lose to an edit that never saw it.
  Future<void> applyRemote(RemoteDoc doc) async {
    final remote = doc.lww;
    final local = await _store.read(doc.path);
    final localClock = local.clocks[NoteFields.text];
    final remoteClock = remote.clocks[NoteFields.text];
    final localText = local.fields[NoteFields.text];
    if (localClock != null &&
        remoteClock != null &&
        localText is String &&
        remoteClock.compareTo(localClock) > 0 &&
        localText != remote.fields[NoteFields.text] &&
        !_history(remote.fields[NoteFields.textHistory]).contains(localClock)) {
      await _store.write('$path/${doc.id}_c_${localClock.replaceAll(':', '_')}', {
        NoteFields.workId: local.fields[NoteFields.workId],
        NoteFields.kind: local.fields[NoteFields.kind],
        NoteFields.text: localText,
        NoteFields.page: local.fields[NoteFields.page],
        NoteFields.location: local.fields[NoteFields.location],
        NoteFields.createdAt: local.fields[NoteFields.createdAt],
        NoteFields.conflictOf: doc.id,
      });
      _onLocalWrite();
    }
    await _store.mergeRemote(doc.path, remote);
  }

  static String? _clean(String text) {
    final t = text.trim();
    return t.isEmpty || t.length > NoteFields.maxTextLength ? null : t;
  }

  static List<String> _history(Object? value) => value is List
      ? [
          for (final v in value)
            if (v is String) v,
        ]
      : const [];

  static List<String> _extendedHistory(Object? value, String? clock) {
    final out = [..._history(value), ?clock];
    return out.length <= NoteFields.maxHistory
        ? out
        : out.sublist(out.length - NoteFields.maxHistory);
  }
}
