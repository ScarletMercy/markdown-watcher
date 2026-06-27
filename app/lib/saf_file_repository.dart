// app/lib/saf_file_repository.dart
//
// Phase 1a Task 2 — the real (Android) FileRepository: pick a .md file via the
// Storage Access Framework (through file_picker) and read its content.
// Phase 1a Task 7 — best-effort write-back.
//
// READ is fully implemented. WRITE is best-effort and documented below.
//
// API verified via context7 + pub.dev + upstream source on 2026-06-27:
//   - file_picker 11.0.2: FilePicker.pickFiles(...) + PlatformFile.{name,path,
//     bytes,identifier}.
//   - saf_util 3.1.0: SafUtil().stat(uri, isDir, {throws}) ->
//     SafDocumentFile{uri, name, isDir, length:int, lastModified:int
//     (epoch ms; 0 = unknown, e.g. some cloud URIs)}.
//   - saf_stream 3.0.0: read APIs (readFileBytes/readFileStream) take a *file*
//     URI; **all write APIs (writeFileBytes/pasteLocalFile/startWriteStream)
//     take a (treeUri, fileName, mime) — there is NO write API that targets a
//     single document/file URI.** file_picker gives us a document URI
//     (ACTION_OPEN_DOCUMENT), not a treeUri, so a clean in-place SAF write-back
//     to the picked file is not expressible with this plugin's API surface.
//     Per the Task 7 risk note we therefore implement the documented FALLBACK:
//     write to app-private storage + keep a .bak, and leave a TODO for a future
//     "export / save-as" flow that uses saf_util.pickDirectory (which *does*
//     return a treeUri with persistable write permission) to write back into
//     the user's chosen tree.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:saf_util/saf_util.dart';

import 'file_repository.dart';

/// Best-effort SAF-aware file repository.
///
/// [pickAndRead] uses file_picker (Android SAF ACTION_OPEN_DOCUMENT under the
/// hood) and returns the document's SAF URI as [MarkdownFile.uri].
///
/// [write] cannot target that document URI in place (saf_stream 3.0.0 write
/// APIs need a treeUri + fileName, see file header). So write is best-effort:
/// it (1) runs an mtime/size conflict probe via saf_util so a future save-as
/// flow can warn the user, (2) snapshots a `.bak` of the previously-mirrored
/// content, and (3) records the new content to an app-private mirror file
/// keyed by the document URI. It never throws — failures are logged via
/// debugPrint so the editor stays responsive.
class SafFileRepository implements FileRepository {
  SafFileRepository({SafUtil? safUtil}) : _saf = safUtil ?? SafUtil();

  final SafUtil _saf;

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
    // write-back / save-as targets the original document. Fall back to path /
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
    // Best-effort: every step is guarded. We never let SAF/platform errors
    // escape to the editor — a failed save must not crash the editor.
    try {
      final uriStr = uri.toString();
      final bytes = utf8.encode(content);

      // (1) Conflict probe via saf_util. stat() on a document URI returns
      //     length + lastModified (epoch ms; 0 when the provider can't report
      //     it, e.g. some cloud URIs). We surface this as a debug warning;
      //     Phase 1a does not block on conflicts — it just tries not to
      //     clobber silently. (We can't write the picked file in place with
      //     saf_stream anyway; this primes a future conflict-warning UI.)
      await _warnIfChanged(uriStr);

      // (2) Crash-recovery .bak of the *previous* mirror content (if any), so a
      //     crash mid-write leaves the user's prior state recoverable. This is
      //     app-private; it is not the user's original file.
      await _snapshotBak(uriStr);

      // (3) Write the new content to the app-private mirror. The actual
      //     user-facing file is NOT updated in place (saf_stream can't target a
      //     document URI — see file header). A future save-as/export flow
      //     (saf_util.pickDirectory -> treeUri -> saf_stream.writeFileBytes)
      //     will flush this mirror into the user's tree.
      await _writeMirror(uriStr, bytes);

      debugPrint('[SafFileRepository] write: mirrored ${bytes.length} bytes '
          'for $uriStr (in-place SAF write not supported by saf_stream 3.0.0; '
          'use save-as to export).');
    } catch (e, st) {
      // Best-effort: swallow. The editor stays responsive; the user can retry.
      debugPrint('[SafFileRepository] write failed (best-effort, swallowed): '
          '$e\n$st');
    }
  }

  /// Probe the document's current mtime/size and warn (debugPrint) about what
  /// we see. Since we can't write the picked file in place, this is
  /// informational for now and primes a future conflict-warning UI. Never
  /// throws — many document URIs won't resolve outside the picker's grant.
  Future<void> _warnIfChanged(String uriStr) async {
    try {
      final doc = await _saf.stat(uriStr, false);
      if (doc == null) return;
      // lastModified == 0 means the provider can't report mtime (common for
      // cloud URIs). In that case size is the only signal available.
      if (doc.lastModified == 0) {
        debugPrint('[SafFileRepository] conflict probe: mtime unavailable for '
            '$uriStr (length=${doc.length}); relying on size only.');
      } else {
        debugPrint('[SafFileRepository] conflict probe: $uriStr '
            'length=${doc.length} lastModified=${doc.lastModified}');
      }
    } catch (e) {
      debugPrint('[SafFileRepository] conflict probe skipped: $e');
    }
  }

  /// Copy the previous mirror content (if present) to `<mirror>.bak` so a crash
  /// during the new write leaves the prior state recoverable.
  Future<void> _snapshotBak(String uriStr) async {
    try {
      final mirror = await _mirrorFile(uriStr);
      if (!await mirror.exists()) return;
      final bak = await _bakFile(uriStr);
      // rename() overwrites on most platforms; if it fails we fall through.
      await mirror.rename(bak.path);
    } catch (e) {
      debugPrint('[SafFileRepository] .bak snapshot skipped: $e');
    }
  }

  Future<void> _writeMirror(String uriStr, List<int> bytes) async {
    final mirror = await _mirrorFile(uriStr);
    // Atomic-ish replace: write to a tmp sibling, then rename over the mirror.
    final tmp = File('${mirror.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(mirror.path);
  }

  /// Resolve a stable app-private path for this document's mirror. The filename
  /// is derived from a cheap hash of the URI so different documents don't
  /// collide; the raw URI isn't filesystem-safe.
  Future<File> _mirrorFile(String uriStr) async {
    final dir = await _mirrorDir();
    return File('${dir.path}/${_safeName(uriStr)}.md');
  }

  Future<File> _bakFile(String uriStr) async {
    final dir = await _mirrorDir();
    return File('${dir.path}/${_safeName(uriStr)}.md$_bakSuffix');
  }

  Future<Directory> _mirrorDir() async {
    // path_provider is not (yet) a dependency and the task forbids adding
    // unverified deps, so we use Directory.systemTemp. systemTemp is cleared by
    // the OS at its discretion; for Phase 1a this is acceptable as a
    // crash-recovery aid, not durable storage. TODO(Task 9+): swap for
    // path_provider's getApplicationDocumentsDirectory once verified.
    final dir = Directory('${Directory.systemTemp.path}/$_mirrorDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Map a document URI to a stable, filesystem-safe basename. Uses a simple
  /// DJB2 hash (no extra deps) plus a short, sanitized suffix of the last path
  /// segment for human readability when inspecting the mirror dir.
  static String _safeName(String uriStr) {
    var hash = 5381;
    for (final c in uriStr.codeUnits) {
      hash = ((hash * 33) ^ c) & 0x7fffffff;
    }
    final last = Uri.tryParse(uriStr)?.pathSegments.lastOrNull ?? 'doc';
    final safeLast = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    final suffix = safeLast.isEmpty ? 'doc' : safeLast;
    return '${hash.toRadixString(16)}_$suffix';
  }

  static const _mirrorDirName = 'markdown_watcher_mirror';
  static const _bakSuffix = '.bak';
}
