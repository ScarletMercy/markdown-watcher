// app/lib/file_repository.dart
//
// Phase 1a Task 1 — the file-access abstraction.
//
// FileRepository is the seam between the editor logic and Android SAF:
//  - SafFileRepository (Task 2/7) does the real pick + read + best-effort write
//    via file_picker / saf_util / saf_stream.
//  - InMemoryFileRepository (below) is a pure-Dart fake used in tests so the
//    editor logic can be exercised with no device.
abstract class FileRepository {
  /// Pick a `.md` file (SAF on Android) and read its content.
  /// Returns null when the user cancels the picker.
  Future<MarkdownFile?> pickAndRead();

  /// Best-effort safe write back to the file at [uri].
  /// The real impl uses SAF `openOutputStream("wt")` + a `.bak` recovery copy
  /// + an mtime/size conflict check (Task 7); the fake just records the bytes.
  Future<void> write(Uri uri, String content);

  /// Export/save-as: prompt for a directory and write [content] there as
  /// [suggestedName]. Returns the newly-written file, or null if the user
  /// cancelled the directory picker.
  ///
  /// This is the export path (distinct from [write], which is the best-effort
  /// autosave mirror): the real impl uses saf_util.pickDirectory to obtain a
  /// treeUri with persistable write permission, then saf_stream.writeFileBytes
  /// to create/overwrite the file in that tree.
  Future<MarkdownFile?> saveAs(String suggestedName, String content);
}

/// A markdown document loaded from (or to be written to) a file.
class MarkdownFile {
  final Uri uri;
  final String name;
  final String content;
  /// Last-modified time from the source; null on URIs that can't report it
  /// (e.g. some cloud URIs). Used by the real write for conflict detection.
  final DateTime? mtime;

  MarkdownFile({
    required this.uri,
    required this.name,
    required this.content,
    this.mtime,
  });
}

/// Pure in-memory fake for tests (no device needed).
///
/// The [store] is keyed by file name on construction (matching how callers
/// seed it, e.g. `{'note.md': ...}`). On [write], the content is recorded under
/// the written `uri.path` so tests can assert round-trips via `store[uri.path]`.
class InMemoryFileRepository implements FileRepository {
  final Map<String, String> store; // path-or-name -> content
  final bool cancel;

  InMemoryFileRepository(this.store, {this.cancel = false});

  @override
  Future<MarkdownFile?> pickAndRead() async {
    if (cancel || store.isEmpty) return null;
    final entry = store.entries.first;
    final uri = Uri.parse('mem:///${entry.key}');
    return MarkdownFile(uri: uri, name: entry.key, content: entry.value);
  }

  @override
  Future<void> write(Uri uri, String content) async {
    store[uri.path] = content;
  }

  @override
  Future<MarkdownFile?> saveAs(String suggestedName, String content) async {
    if (cancel) return null;
    // The fake models a successful export: record the content under an
    // export:// URI keyed by the suggested name and return it as a MarkdownFile.
    final uri = Uri.parse('export:///$suggestedName');
    store[uri.toString()] = content;
    return MarkdownFile(uri: uri, name: suggestedName, content: content);
  }
}
