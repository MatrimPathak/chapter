import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../application/data_exporter.dart';

enum DeleteAccountOutcome { deleted, needsRecentSignIn, failed }

/// The server half of account deletion.
abstract interface class AccountRemote {
  Future<DeleteAccountOutcome> deleteAccount();
}

class CallableAccountRemote implements AccountRemote {
  const CallableAccountRemote(this._functions);

  final FirebaseFunctions _functions;

  // Matches the function's own limit: a large library is many small deletes.
  static const _timeout = Duration(minutes: 5);

  @override
  Future<DeleteAccountOutcome> deleteAccount() async {
    try {
      await _functions
          .httpsCallable('deleteAccount', options: HttpsCallableOptions(timeout: _timeout))
          .call<Object?>();
      return DeleteAccountOutcome.deleted;
    } on FirebaseFunctionsException catch (e) {
      return e.code == 'failed-precondition'
          ? DeleteAccountOutcome.needsRecentSignIn
          : DeleteAccountOutcome.failed;
    }
  }
}

/// Hands export files to the system share sheet.
abstract interface class ExportSharer {
  Future<void> share(List<ExportFile> files);
}

class SystemExportSharer implements ExportSharer {
  const SystemExportSharer();

  @override
  Future<void> share(List<ExportFile> files) async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/chapter-export');
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create();
    try {
      final paths = <String>[];
      for (final f in files) {
        final file = File('${dir.path}/${f.name}');
        await file.writeAsString(f.content);
        paths.add(file.path);
      }
      await SharePlus.instance.share(ShareParams(files: [for (final p in paths) XFile(p)]));
    } finally {
      // The share plugin keeps its own copy for the receiving app.
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  }
}

/// Removes an account's data from this device. The marker means a kill between
/// the server deleting the account and the wipe finishes on the next launch.
abstract interface class LocalDataWiper {
  Future<void> markPending(String uid);

  /// Finishes every marked wipe. Never throws; a marker that couldn't be
  /// finished stays for the next launch.
  Future<void> finishPending();
}

class FileLocalDataWiper implements LocalDataWiper {
  const FileLocalDataWiper();

  static const _prefix = '.chapter_wipe_';

  @override
  Future<void> markPending(String uid) async {
    final docs = await getApplicationDocumentsDirectory();
    await File('${docs.path}/$_prefix${AppDatabase.safeFileName(uid)}').create();
  }

  @override
  Future<void> finishPending() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final markers = docs.listSync().whereType<File>().where(
        (f) => f.uri.pathSegments.last.startsWith(_prefix),
      );
      for (final marker in markers.toList()) {
        final safe = marker.uri.pathSegments.last.substring(_prefix.length);
        for (final suffix in const ['', '-wal', '-shm', '-journal']) {
          final db = File('${docs.path}/chapter_$safe.sqlite$suffix');
          if (db.existsSync()) await db.delete();
        }
        await _clearTemporaryFiles();
        await marker.delete();
      }
    } on Object {
      // The marker stays; the next launch tries again.
    }
  }

  /// Covers and any export copies: they reveal what was being read.
  static Future<void> _clearTemporaryFiles() async {
    final temp = await getTemporaryDirectory();
    if (!temp.existsSync()) return;
    for (final entry in temp.listSync()) {
      try {
        await entry.delete(recursive: true);
      } on FileSystemException {
        // In use by the system; it's the OS's cache to clear.
      }
    }
  }
}
