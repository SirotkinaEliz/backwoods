import Foundation
import SwiftSignalKit

// Backwoods: SwiftSignalKit Test Helpers
// Utilities for testing Signal-based code synchronously.

/// Collects all values emitted by a Signal into an array.
/// Blocks the current thread until the signal completes or timeout is reached.
public func collectValues<T, E>(
    _ signal: Signal<T, E>,
    timeout: TimeInterval = 5.0
) -> Result<[T], E> {
    var values: [T] = []
    var error: E?
    let expectation = DispatchSemaphore(value: 0)
    var completed = false
    
    let disposable = signal.start(
        next: { value in
            values.append(value)
        },
        error: { e in
            error = e
            expectation.signal()
        },
        completed: {
            completed = true
            expectation.signal()
        }
    )
    
    let result = expectation.wait(timeout: .now() + timeout)
    
    if result == .timedOut {
        disposable.dispose()
    }
    
    if let error = error {
        return .failure(error)
    }
    return .success(values)
}

/// Collects the first N values from a Signal.
public func collectFirst<T, E>(
    _ count: Int,
    from signal: Signal<T, E>,
    timeout: TimeInterval = 5.0
) -> [T] {
    var values: [T] = []
    let expectation = DispatchSemaphore(value: 0)
    
    let disposable = signal.start(next: { value in
        values.append(value)
        if values.count >= count {
            expectation.signal()
        }
    })
    
    let _ = expectation.wait(timeout: .now() + timeout)
    disposable.dispose()
    
    return values
}

/// Waits for a single value from a Signal.
public func awaitValue<T, E>(
    _ signal: Signal<T, E>,
    timeout: TimeInterval = 5.0
) -> T? {
    let values = collectFirst(1, from: signal, timeout: timeout)
    return values.first
}

/// Expects that a Signal emits an error.
public func expectError<T, E>(
    _ signal: Signal<T, E>,
    timeout: TimeInterval = 5.0
) -> E? {
    let result = collectValues(signal, timeout: timeout)
    switch result {
    case .success:
        return nil
    case .failure(let error):
        return error
    }
}

/// Creates a Signal that emits a single value immediately.
public func just<T>(_ value: T) -> Signal<T, NoError> {
    return Signal { subscriber in
        subscriber.putNext(value)
        subscriber.putCompletion()
        return EmptyDisposable
    }
}

/// Creates a Signal that emits an error immediately.
public func fail<T, E>(_ error: E) -> Signal<T, E> {
    return Signal { subscriber in
        subscriber.putError(error)
        return EmptyDisposable
    }
}

/// Creates a Signal that never completes (for testing disposable cleanup).
public func never<T>() -> Signal<T, NoError> {
    return Signal { _ in
        return EmptyDisposable
    }
}

/// Collects values emitted during a specific time window.
public func collectDuring<T, E>(
    _ signal: Signal<T, E>,
    duration: TimeInterval
) -> [T] {
    var values: [T] = []
    
    let disposable = signal.start(next: { value in
        values.append(value)
    })
    
    Thread.sleep(forTimeInterval: duration)
    disposable.dispose()
    
    return values
}
