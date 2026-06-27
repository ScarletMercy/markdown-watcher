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
