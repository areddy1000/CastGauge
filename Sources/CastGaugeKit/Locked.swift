import Synchronization

/// A reference to a value behind a mutex. Escaping closures can capture it.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        mutex.withLock { body(&$0) }
    }
}
