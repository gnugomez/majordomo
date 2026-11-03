// One stream per subscriber over one of the engine's outputs. An
// AsyncStream has a single consumer, so each subscriber gets a stream of
// its own, buffered as it asks: the state's latest-wins (a reader that
// falls behind only needs the newest), the events' every one in order.

/// Not Sendable by design: a value the engine actor owns and yields from.
struct Broadcast<Element: Sendable> {
  /// Whether a new subscriber first hears the latest element.
  private let replaysLatest: Bool
  private var latest: Element?
  private var subscribers: [AsyncStream<Element>.Continuation] = []

  init(replaysLatest: Bool) {
    self.replaysLatest = replaysLatest
  }

  mutating func subscribe(
    buffering policy: AsyncStream<Element>.Continuation.BufferingPolicy
  ) -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: policy)
    if replaysLatest, let latest {
      continuation.yield(latest)
    }
    subscribers.append(continuation)
    return stream
  }

  /// Hands the element to every subscriber, letting go of those that
  /// stopped listening.
  mutating func yield(_ element: Element) {
    if replaysLatest {
      latest = element
    }
    var listening: [AsyncStream<Element>.Continuation] = []
    for subscriber in subscribers {
      if case .terminated = subscriber.yield(element) {
        continue
      }
      listening.append(subscriber)
    }
    subscribers = listening
  }

  /// Ends every subscriber's stream.
  mutating func finish() {
    for subscriber in subscribers {
      subscriber.finish()
    }
    subscribers = []
  }
}
