import 'package:meta/meta.dart';

enum NoteKind {
  note,
  quote,
  observation;

  static NoteKind parse(Object? v) =>
      values.firstWhere((k) => k.name == v, orElse: () => NoteKind.note);
}

/// Field names of `users/{uid}/notes/{id}`, validated by firestore.rules.
abstract final class NoteFields {
  static const workId = 'workId';
  static const kind = 'kind';
  static const text = 'text';
  static const page = 'page';
  static const location = 'location';
  static const createdAt = 'createdAt';
  static const conflictOf = 'conflictOf';
  static const deleted = 'deleted';

  /// Clocks of the text versions this one was edited from, newest last.
  /// Lets another device tell "edited from mine" from "edited at the same time".
  static const textHistory = 'textHistory';

  static const maxTextLength = 10000;
  static const maxHistory = 20;
}

@immutable
class Note {
  const Note({
    required this.id,
    required this.workId,
    required this.kind,
    required this.text,
    required this.createdAt,
    this.page,
    this.location,
    this.conflictOf,
  });

  /// `null` for tombstoned or incomplete documents.
  static Note? fromFields(String id, Map<String, Object?> f) {
    if (f[NoteFields.deleted] == true) return null;
    final workId = f[NoteFields.workId];
    final text = f[NoteFields.text];
    final created = DateTime.tryParse(f[NoteFields.createdAt] as String? ?? '');
    if (workId is! String || text is! String || created == null) return null;
    return Note(
      id: id,
      workId: workId,
      kind: NoteKind.parse(f[NoteFields.kind]),
      text: text,
      createdAt: created,
      page: (f[NoteFields.page] as num?)?.toInt(),
      location: (f[NoteFields.location] as num?)?.toInt(),
      conflictOf: f[NoteFields.conflictOf] as String?,
    );
  }

  final String id;
  final String workId;
  final NoteKind kind;
  final String text;
  final DateTime createdAt;

  /// Optional page anchor.
  final int? page;

  /// Kindle location, from a clippings import.
  final int? location;

  /// Set on a copy kept because this text was edited on two devices at once.
  final String? conflictOf;

  bool get isConflictCopy => conflictOf != null;
}
