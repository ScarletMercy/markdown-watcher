import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_watcher/debouncer.dart';

void main() {
  test('only fires the last call after the window', () async {
    final d = Debouncer(Duration(milliseconds: 50));
    var calls = 0;
    d.run(() => calls++);
    d.run(() => calls++);
    d.run(() => calls++);
    await Future.delayed(Duration(milliseconds: 120));
    expect(calls, 1); // only the last
  });

  test('dispose() cancels a pending call', () async {
    final d = Debouncer(Duration(milliseconds: 50));
    var calls = 0;
    d.run(() => calls++);
    d.dispose();
    await Future.delayed(Duration(milliseconds: 120));
    expect(calls, 0); // cancelled, never fires
  });
}
