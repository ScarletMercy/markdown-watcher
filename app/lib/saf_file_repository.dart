// app/lib/saf_file_repository.dart
//
// Phase 1a Task 2 — the real (Android) FileRepository: pick a .md file via the
// Storage Access Framework (through file_picker) and read its content.
//
// READ is fully implemented here. WRITE (best-effort SAF write-back via
// saf_util/saf_stream) is implemented in Task 7; until then it throws.
//
// API verified against file_picker 11.0.2 (context7, 2026-06-27):
//   FilePicker.platform.pickFiles(type, allowedExtensions, withData) and
//   PlatformFile.{name, path, bytes, identifier}.
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'file_repository.dart';

class SafFileRepository implements FileRepository {
  @override
  Future<MarkdownFile?> pickAndRead() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md'],
      // withData: read bytes into memory so we can decode without a second IO.
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final f = result.files.single;
    final content = await _readContent(f);
    // On Android the durable SAF URI lives in `identifier` (a content:// URI);
    // `path` is a cached-copy path. Prefer identifier for the uri we keep, so
    // Task 7's write-back targets the original document. Fall back to path /
    // empty so we never parse null.
    return MarkdownFile(
      uri: Uri.parse(f.identifier ?? f.path ?? ''),
      name: f.name,
      content: content,
    );
  }

  /// Decode the picked file's bytes, preferring the in-memory copy (withData)
  /// and falling back to reading the cached path.
  Future<String> _readContent(PlatformFile f) async {
    if (f.bytes != null) return String.fromCharCodes(f.bytes!);
    if (f.path != null) return await File(f.path!).readAsString();
    return '';
  }

  @override
  Future<void> write(Uri uri, String content) async {
    // Implemented in Task 7 (best-effort SAF write-back).
    throw UnimplementedError('SafFileRepository.write — implemented in Task 7');
  }
}
