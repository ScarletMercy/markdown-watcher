// app/test/file_repository_fake_test.dart
//
// Phase 1a Task 1 — TDD for the FileRepository fake.
// These tests define the InMemoryFileRepository contract used in place of the
// real SAF repo for pure-Dart (no-device) testing.
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_watcher/file_repository.dart';

void main() {
  test('InMemoryFileRepository picks and reads back content', () async {
    final repo = InMemoryFileRepository({'note.md': '# Hello'});
    final file = await repo.pickAndRead();
    expect(file, isNotNull);
    expect(file!.name, 'note.md');
    expect(file.content, '# Hello');
  });

  test('write then re-read returns the new content', () async {
    final repo = InMemoryFileRepository({'note.md': 'old'});
    final file = (await repo.pickAndRead())!;
    await repo.write(file.uri, 'new content');
    expect(repo.store[file.uri.path], 'new content');
  });

  test('pickAndRead returns null when user cancels', () async {
    final repo = InMemoryFileRepository({}, cancel: true);
    expect(await repo.pickAndRead(), isNull);
  });

  // Phase 1a Task 7 (save-as/export) — the export contract for the fake.
  group('saveAs', () {
    test('writes content and returns the file', () async {
      final repo = InMemoryFileRepository({});
      final file = await repo.saveAs('exported.md', '# Exported');
      expect(file, isNotNull);
      expect(file!.name, 'exported.md');
      expect(file.content, '# Exported');
      // The content is recorded under an export:// URI so callers/tests can
      // assert round-trips against the same store used by write().
      expect(repo.store[file.uri.toString()], '# Exported');
    });

    test('returns null when user cancels', () async {
      final repo = InMemoryFileRepository({}, cancel: true);
      expect(await repo.saveAs('exported.md', 'x'), isNull);
    });
  });
}
