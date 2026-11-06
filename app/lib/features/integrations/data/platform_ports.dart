import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link in another app or the browser. Overridden in tests.
abstract interface class LinkOpener {
  /// `false` if nothing could open it.
  Future<bool> open(Uri uri);
}

class UrlLauncherLinkOpener implements LinkOpener {
  const UrlLauncherLinkOpener();

  @override
  Future<bool> open(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
}

class FileTooLargeException implements Exception {
  const FileTooLargeException();
}

/// Lets the reader choose a file. Overridden in tests.
abstract interface class TextFilePicker {
  /// The file's text, or `null` if the reader backed out.
  Future<String?> pick(List<String> extensions);
}

class SystemTextFilePicker implements TextFilePicker {
  const SystemTextFilePicker();

  static const maxBytes = 20 * 1024 * 1024;

  @override
  Future<String?> pick(List<String> extensions) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions);
    if (file == null) return null;
    final length = await file.length();
    if (length != null && length > maxBytes) throw const FileTooLargeException();
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) throw const FileTooLargeException();
    return utf8.decode(bytes, allowMalformed: true);
  }
}
