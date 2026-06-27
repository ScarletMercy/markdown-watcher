# Phase 1a — Core Editor Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the rendering probe into a minimal usable editor: open a `.md` file → edit in a native TextField → live preview (reusing the verified bundle) → autosave back to the file.

**Architecture:** A Riverpod-managed `EditorScreen` hosts an adaptive layout (portrait = tab edit/preview, landscape = side-by-side). `FileRepository` abstracts Android SAF read/write (with a fake for tests). The existing `WebViewBridge` + `preview/` bundle + `InAppLocalhostServer` render the editor's text (debounced). Autosave debounces text changes and writes via SAF best-effort (`openOutputStream("wt")` + `.bak` + mtime conflict check).

**Tech Stack:** Flutter (Dart), Riverpod v3, `file_picker` + `saf_util`/`saf_stream` (Android SAF — versions to verify via context7 at execution per project policy), existing `flutter_inappwebview` + preview bundle. TDD for pure logic; device/CI verification for UI + SAF.

**Scope (Phase 1a — IN):** open/read (SAF), native editor + basic toolbar, live preview, adaptive portrait/landscape, autosave-back (SAF best-effort).
**Scope (Phase 1b — DEFERRED):** bidirectional scroll-sync, 3-theme UI + follow-system, large-file threshold, background draft recovery, Find/Replace, full toolbar (tables/images).

**Reused as-is (do NOT rebuild):** `preview/` JS bundle (29 tests), `app/lib/bridge_encoding.dart` (pure encoder), `app/lib/webview_bridge.dart` (render/renderDone/renderCounts), `InAppLocalhostServer` setup, the `.github/workflows/verify.yml` (CI still builds + tests + releases).

**Environment:** Local dev on Windows (Flutter + Android SDK installed; no emulator image — runtime checks via CI + real device). The `android/` folder is CI-generated with sed patches (proguard/cleartext/INTERNET); **Task 0 recommends committing a pre-configured `android/` folder** so local builds work without replicating patches.

---

## Task 0 (recommended prerequisite): Commit a pre-configured `android/` folder

**Why:** Phase 1 needs frequent local `flutter run` on a device/emulator. Currently `android/` is CI-generated + 3 sed patches (proguard, cleartext, INTERNET) — local builds would need to replicate them manually. Committing one configured `android/` makes local dev work out of the box AND removes the CI sed steps.

**Files:**
- Create: `app/android/` (full Flutter Android scaffold with the 3 fixes baked in)
- Modify: `.github/workflows/verify.yml` (drop `flutter create --platforms=android` + the 3 sed patches; keep KVM, test, build, release)
- Modify: `app/.gitignore` (un-ignore `android/`)

**Steps:**
1. Locally run `cd app && flutter create --platforms=android --project-name=markdown_watcher .`
2. Apply the 3 fixes to `app/android/app/src/main/AndroidManifest.xml` + the plugin proguard:
   - Add `<uses-permission android:name="android.permission.INTERNET"/>` before `<application>`
   - Add `android:usesCleartextTraffic="true"` on `<application>`
   - (proguard is in the plugin's build.gradle — keep the CI sed OR add a Gradle `subprojects` override in `app/android/build.gradle` that forces `proguard-android-optimize.txt`)
3. Un-ignore `android/` in `app/.gitignore` (remove the `android/` line).
4. Commit `app/android/`. Verify local `flutter build apk --debug` works (no patches needed).
5. Simplify `verify.yml` android job: remove the `flutter create` + proguard/cleartext/INTERNET sed steps (now baked in); keep KVM + emulator test + debug build + release.
6. **Verify the CI still passes** after the simplification (push, watch the run).

**Commit:** `feat(app): commit pre-configured android/ (proguard+cleartext+INTERNET baked in)`

> This is a one-time setup that pays off for all of Phase 1. If you'd rather not commit `android/` yet, skip Task 0 and keep the CI sed patches (local dev will need manual patch replication).

---

## Task 1: Add file-access deps + `FileRepository` interface + fake

**Files:**
- Modify: `app/pubspec.yaml` (add `file_picker`, `saf_util`, `saf_stream`, `path` — verify versions via context7)
- Create: `app/lib/file_repository.dart`
- Create: `app/test/file_repository_fake_test.dart`

**Step 1: Add deps to `app/pubspec.yaml`** (verify each is current via context7/pub.dev before locking — project policy):
```yaml
dependencies:
  # ...existing...
  file_picker: ^11.0.2       # verify current
  saf_util: ^3.1.0           # verify current
  saf_stream: ^1.x.x         # verify current (SAF stream read/write)
  path: ^1.9.0
```

**Step 2: Write the failing test** (the fake's behavior — pure, no device):
```dart
// app/test/file_repository_fake_test.dart
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
    final file = await repo.pickAndRead()!;
    await repo.write(file.uri, 'new content');
    expect(repo.store[file.uri.path], 'new content');
  });

  test('pickAndRead returns null when user cancels', () async {
    final repo = InMemoryFileRepository({}, cancel: true);
    expect(await repo.pickAndRead(), isNull);
  });
}
```

**Step 3: Implement the interface + fake:**
```dart
// app/lib/file_repository.dart
abstract class FileRepository {
  /// Pick a .md file (SAF on Android) and read its content. Returns null on cancel.
  Future<MarkdownFile?> pickAndRead();
  /// Best-effort safe write (SAF openOutputStream("wt") + .bak + mtime check on the real impl).
  Future<void> write(Uri uri, String content);
}

class MarkdownFile {
  final Uri uri;
  final String name;
  final String content;
  final DateTime? mtime;
  MarkdownFile({required this.uri, required this.name, required this.content, this.mtime});
}

/// Pure in-memory fake for tests (no device needed).
class InMemoryFileRepository implements FileRepository {
  final Map<String, String> store; // path -> content
  final bool cancel;
  InMemoryFileRepository(this.store, {this.cancel = false});
  final Map<String, String> _byPath = {};

  @override
  Future<MarkdownFile?> pickAndRead() async {
    if (cancel || store.isEmpty) return null;
    final entry = store.entries.first;
    final uri = Uri.parse('mem:///${entry.key}');
    _byPath[uri.path] = entry.value;
    return MarkdownFile(uri: uri, name: entry.key, content: entry.value);
  }

  @override
  Future<void> write(Uri uri, String content) async {
    _byPath[uri.path] = content;
    store[uri.path.split('/').last] = content;
  }
}
```

**Step 4: Run test → pass.** **Step 5: Commit** `feat(app): FileRepository interface + in-memory fake`

---

## Task 2: SAF `FileRepository` impl (Android) — READ

**Files:**
- Create: `app/lib/saf_file_repository.dart`

**Step 1: Implement SAF read via file_picker** (verify exact API via context7 — file_picker's Android behavior for picking + reading):
```dart
// app/lib/saf_file_repository.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'file_repository.dart';

class SafFileRepository implements FileRepository {
  @override
  Future<MarkdownFile?> pickAndRead() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    final content = await _readContent(f);
    return MarkdownFile(
      uri: Uri.parse(f.path ?? f.identifier ?? ''),
      name: f.name,
      content: content,
    );
  }

  Future<String> _readContent(PlatformFile f) async {
    if (f.bytes != null) return String.fromCharCodes(f.bytes!);
    if (f.path != null) return await File(f.path!).readAsString();
    return '';
  }

  @override
  Future<void> write(Uri uri, String content) async {
    // Task 7 implements best-effort SAF write-back.
    throw UnimplementedError('write implemented in Task 7');
  }
}
```

> **VERIFY via context7:** file_picker's Android pick returns a cached copy path for reading (good), but for WRITE-BACK to the original location you need the persisted SAF URI (Task 7 uses saf_util). Confirm `withData`/`path`/`identifier` behavior on current file_picker before relying on it.

**Step 2:** Cannot fully test locally (needs device). Static check: `cd app && flutter analyze --no-fatal-infos` clean.

**Step 3: Commit** `feat(app): SafFileRepository read via file_picker`

---

## Task 3: Markdown toolbar insertion logic — TDD (pure)

**Files:**
- Create: `app/lib/editor_actions.dart`
- Create: `app/test/editor_actions_test.dart`

**Step 1: Failing test:**
```dart
// app/test/editor_actions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_watcher/editor_actions.dart';

void main() {
  group('wrapSelection', () {
    test('wraps selected text with prefix/suffix', () {
      final r = wrapSelection('hello world', TextRange(0, 5), '**', '**');
      expect(r.text, '**hello** world');
      expect(r.selection.start, 2);
      expect(r.selection.end, 7);
    });
    test('no selection inserts placeholder and places cursor inside', () {
      final r = wrapSelection('abc', TextRange(3, 3), '**', '**');
      expect(r.text, 'abc****');
      expect(r.selection.start, 5); // cursor between the ** **? -> between placeholder
    });
  });
  group('toggleLinePrefix', () {
    test('adds "- " to start of line at cursor', () {
      final r = toggleLinePrefix('line1\nline2', TextRange(6, 6), '- ');
      expect(r.text, 'line1\n- line2');
    });
  });
}
```

**Step 2: Implement:**
```dart
// app/lib/editor_actions.dart
import 'package:flutter/widgets.dart';

class EditResult { final String text; final TextRange selection; EditResult(this.text, this.selection); }

/// Wrap the selection [base..extent] with prefix/suffix (e.g. ** for bold).
EditResult wrapSelection(String text, TextRange sel, String prefix, String suffix) {
  final start = sel.start.clamp(0, text.length);
  final end = sel.end.clamp(0, text.length);
  if (start == end) {
    final placeholder = 'text';
    final newText = text.replaceRange(start, end, '$prefix$placeholder$suffix');
    return EditResult(newText, TextRange(start + prefix.length, start + prefix.length + placeholder.length));
  }
  final selected = text.substring(start, end);
  final newText = text.replaceRange(start, end, '$prefix$selected$suffix');
  return EditResult(newText, TextRange(start + prefix.length, end + prefix.length));
}

/// Toggle a line prefix (e.g. "- ", "# ") at the start of the line containing the cursor.
EditResult toggleLinePrefix(String text, TextRange sel, String prefix) {
  final i = sel.start.clamp(0, text.length);
  final lineStart = (i == 0) ? 0 : text.lastIndexOf('\n', i - 1) + 1;
  final newText = text.replaceRange(lineStart, lineStart, prefix);
  return EditResult(newText, TextRange(i + prefix.length, i + prefix.length));
}
```
> Fix the no-selection cursor math so the test passes (the test asserts a specific position — iterate until green).

**Step 3: Run → pass. Iterate the no-selection case until the test's assertion holds.** **Step 4: Commit** `feat(app): markdown toolbar insertion logic`

---

## Task 4: Debouncer — TDD (pure)

**Files:** Create `app/lib/debouncer.dart`, Create `app/test/debouncer_test.dart`

**Step 1: Failing test:**
```dart
test('only fires the last call after the window', () async {
  final d = Debouncer(Duration(milliseconds: 50));
  var calls = 0;
  d.run(() => calls++);
  d.run(() => calls++);
  d.run(() => calls++);
  await Future.delayed(Duration(milliseconds: 120));
  expect(calls, 1); // only the last
});
```
**Step 2: Implement:**
```dart
import 'dart:async';
class Debouncer {
  final Duration delay;
  Timer? _t;
  Debouncer(this.delay);
  void run(void Function() action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }
  void dispose() => _t?.cancel();
}
```
**Step 3: Run → pass. Commit** `feat(app): Debouncer`

---

## Task 5: Riverpod state — current document, editor text, dirty

**Files:** Create `app/lib/editor_state.dart`

**Step 1: Implement providers** (Riverpod v3; verify codegen vs manual style — manual NotifierProvider is fine for Phase 1a, avoids build_runner complexity):
```dart
// app/lib/editor_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'file_repository.dart';

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  throw UnimplementedError('override in main with SafFileRepository (prod) or InMemoryFileRepository (test)');
});

class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => EditorState();

  void loadFile(MarkdownFile f) => state = state.copy(file: f, text: f.content, dirty: false);
  void updateText(String t) => state = state.copy(text: t, dirty: true);
}

final editorProvider = NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

class EditorState {
  final MarkdownFile? file;
  final String text;
  final bool dirty;
  EditorState({this.file, this.text = '', this.dirty = false});
  EditorState copy({MarkdownFile? file, String? text, bool? dirty}) =>
      EditorState(file: file ?? this.file, text: text ?? this.text, dirty: dirty ?? this.dirty);
}
```
**Step 2: analyze clean.** **Step 3: Commit** `feat(app): Riverpod editor state`

---

## Task 6: Editor widget (TextField + toolbar) + live preview wiring

**Files:**
- Create: `app/lib/editor_widget.dart` (TextField + toolbar using editor_actions)
- Create: `app/lib/preview_widget.dart` (wraps InAppLocalhostServer + WebViewBridge, renders editor text debounced)
- Modify: `app/lib/main.dart` (replace probe with real app — Task 9 ties together)

**Step 1: PreviewWidget** — reuses WebViewBridge + InAppLocalhostServer (proven in probe). Debounce text → `bridge.render(text)`. Key code:
```dart
// app/lib/preview_widget.dart
class PreviewWidget extends ConsumerStatefulWidget { ... }
// initState: start InAppLocalhostServer(documentRoot: 'assets/preview') (same as probe)
// didChangeDependencies: watch editorProvider.text, debounce 400ms, bridge.render(text, theme)
// onLoadStop: installDoneHandler (reuse from WebViewBridge)
```

**Step 2: EditorWidget** — TextField (monospace) + a toolbar row (Bold/Italic/H1/H2/List/Code/Link) wired to `editor_actions` via the controller's selection.

**Step 3:** analyze clean. **Step 4: Commit** `feat(app): editor + preview widgets`

> Full widget code is verbose; the implementer writes it following Flutter idioms, reusing `WebViewBridge` and `editor_actions`. The injection-safe render path (JSON-encoded via `bridge_encoding.dart`) is unchanged.

---

## Task 7: SAF write-back (best-effort) — the hard part

**Files:** Modify `app/lib/saf_file_repository.dart` (implement `write`)

**Step 1: Implement best-effort write** (verify saf_util/saf_stream current API via context7 — this is the design's P0(c) risk area):
- Persist the picked file's SAF URI (file_picker returns `identifier` on Android = the SAF URI; cache it).
- On write: `saf_stream`'s `writeFileBytes(uri, bytes, overwrite: true)` OR `ContentResolver.openOutputStream(uri, "wt")` equivalent.
- Best-effort safety (per design §5): before write, check mtime/size vs loaded; write via the SAF stream (URI never disappears); keep a `.bak` of the previous content in app-private storage as crash recovery.
- mtime may be null on cloud URIs → defensive fallback (size + head/tail bytes).

**Step 2:** No local test (needs device). The integration_test (Task 9) or a manual device run verifies it.

**Step 3: Commit** `feat(app): SAF best-effort write-back`

> **This is the riskiest task.** If saf_util/saf_stream's API differs from assumptions, verify via context7 and adapt. The design's runbook (PHASE0-DEVICE-RUNBOOK.md P0(c)) documents the expected behavior. If SAF write proves too fragile, fallback: write to app-private storage + offer "export/save-as" via picker (less seamless but reliable).

---

## Task 8: Adaptive layout (portrait tab / landscape split)

**Files:** Create `app/lib/editor_screen.dart`

**Step 1:** Use `LayoutBuilder`: width < 600 → `TabBarView`(Editor, Preview); width ≥ 600 → `Row`(Editor, Preview) with a drag handle. Defer scroll-sync (Phase 1b).

**Step 2:** analyze clean. **Step 3: Commit** `feat(app): adaptive editor screen`

---

## Task 9: Wire it all into `main.dart` + a "Open file" entry

**Files:** Modify `app/lib/main.dart`

**Step 1:** Replace the probe with:
```dart
void main() {
  runApp(ProviderScope(
    overrides: [fileRepositoryProvider.overrideWithValue(SafFileRepository())],
    child: const MaterialApp(home: EditorScreen()),
  ));
}
```
EditorScreen has an AppBar action "Open" → `ref.read(fileRepositoryProvider).pickAndRead()` → `editorNotifier.loadFile(...)`. Autosave: a listener on `editorProvider` debounces and calls `write` when dirty.

**Step 2:** The old `ProbePage` — either delete or move to a hidden route (keep the integration_test working). Simplest: keep `render_probe_test.dart` testing the preview rendering path; add a new editor integration test in Phase 1b.

**Step 3:** analyze clean + unit tests green. **Step 4: Commit** `feat(app): wire editor loop into main`

---

## Task 10: Update CI + ship a Phase 1a release

**Files:** Modify `.github/workflows/verify.yml` (if Task 0 simplified it), tag `v0.2.0`

**Step 1:** Ensure CI: analyze + unit tests + integration_test (preview render still works) + debug APK artifact + release APK on tag.
**Step 2:** Push main → CI green.
**Step 3:** `git tag v0.2.0 && git push origin v0.2.0` → release the Phase 1a APK.
**Step 4:** Install on device → open a .md file → edit → see preview → verify it saved (reopen).

---

## Done criteria for Phase 1a
- Open a `.md` from the device → content loads in the editor.
- Type/edit → live preview updates (debounced).
- Autosave writes back to the file (best-effort; verify by reopening).
- Portrait = tabs, landscape = split.
- `flutter analyze` clean; unit tests (toolbar, debouncer, FileRepository fake) green; preview integration_test green.
- `v0.2.0` release APK installs and does the loop on a real device.

## Known risks
- **SAF write-back (Task 7)** is the riskiest — verify saf_util/saf_stream API; fallback to app-private + export if needed.
- **file_picker Android URI persistence** for write-back — verify `identifier` is the SAF URI and persists across the session.
- **No local device** for runtime checks — verify via CI emulator + real device sideload.

## Next (Phase 1b)
Bidirectional scroll-sync, 3-theme UI + follow-system, large-file threshold, background draft recovery, Find/Replace, full toolbar.
