import 'dart:async';

/// A single request's stop signal; never reused for a subsequent reply.
class GenerationControl {
  final _stopped = Completer<void>();
  bool get isStopped => _stopped.isCompleted;
  Future<void> get whenStopped => _stopped.future;
  bool keepPartial = true;
  void stop({bool discardPartial = false}) {
    if (isStopped) return;
    keepPartial = !discardPartial;
    _stopped.complete();
  }

  /// Closes promptly even when an async generator is waiting for its next
  /// event. Canceling the underlying subscription alone can wait indefinitely.
  Stream<T> untilStopped<T>(Stream<T> source) {
    late StreamController<T> output;
    StreamSubscription<T>? subscription;
    void cancelSource() {
      final pending = subscription?.cancel();
      if (pending != null) unawaited(pending.catchError((Object _) {}));
    }

    output = StreamController<T>(
      onListen: () {
        if (isStopped) {
          unawaited(output.close());
          return;
        }
        subscription = source.listen(
          (value) {
            if (!isStopped && !output.isClosed) output.add(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!isStopped && !output.isClosed) output.addError(error, stack);
          },
          onDone: () {
            if (!output.isClosed) unawaited(output.close());
          },
        );
        whenStopped.then((_) {
          cancelSource();
          if (!output.isClosed) unawaited(output.close());
        });
      },
      onCancel: cancelSource,
    );
    return output.stream;
  }
}
