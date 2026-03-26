import Foundation
import SwiftSignalKit
import TunnelKit

// Backwoods: TunnelManager SwiftSignalKit extensions
// Provides reactive signal-based API for tunnel operations,
// following Telegram's existing patterns with |> operator.

public extension TunnelManager {
    
    /// Signal that emits true when tunnel is connected, false otherwise.
    /// Useful for UI bindings.
    var isConnected: Signal<Bool, NoError> {
        return status
        |> map { status -> Bool in
            if case .connected = status {
                return true
            }
            return false
        }
        |> distinctUntilChanged
    }
    
    /// Signal that emits true when tunnel is in a transient state
    /// (connecting, reconnecting, disconnecting).
    var isTransitioning: Signal<Bool, NoError> {
        return status
        |> map { status -> Bool in
            switch status {
            case .connecting, .reconnecting, .disconnecting:
                return true
            default:
                return false
            }
        }
        |> distinctUntilChanged
    }
    
    /// Signal that emits the error when tunnel enters failed state.
    var error: Signal<TransportError?, NoError> {
        return status
        |> map { status -> TransportError? in
            if case .failed(let error) = status {
                return error
            }
            return nil
        }
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case (.some(let l), .some(let r)):
                return l == r
            default:
                return false
            }
        })
    }
    
    /// Human-readable status string for UI display
    var statusText: Signal<String, NoError> {
        return status
        |> map { status -> String in
            switch status {
            case .disconnected:
                return "Отключено"
            case .connecting:
                return "Подключение..."
            case .connected:
                return "Подключено"
            case .reconnecting:
                return "Переподключение..."
            case .disconnecting:
                return "Отключение..."
            case .failed(let error):
                return "Ошибка: \(error.localizedDescription)"
            }
        }
    }
    
    /// Connect with exponential backoff retry.
    /// Retries up to TunnelConstants.retryMaxAttempts times with increasing delays.
    ///
    /// - Returns: Signal that completes when connected or errors after max retries
    func connectWithRetry() -> Signal<Void, TransportError> {
        return ensureConnected()
        |> retryWithBackoff(
            retryCount: TunnelConstants.retryMaxAttempts,
            initialDelay: TunnelConstants.retryInitialDelay,
            maxDelay: TunnelConstants.retryMaxDelay
        )
    }
}

// MARK: - Custom retry with backoff operator

/// Retry a signal with exponential backoff.
/// Follows Telegram's SwiftSignalKit patterns.
public func retryWithBackoff<T, E: Error>(
    retryCount: Int,
    initialDelay: TimeInterval,
    maxDelay: TimeInterval
) -> (Signal<T, E>) -> Signal<T, E> {
    return { signal in
        return Signal { subscriber in
            let currentAttempt = Atomic<Int>(value: 0)
            let disposable = MetaDisposable()
            
            func attempt() {
                let attemptDisposable = signal.start(
                    next: { value in
                        subscriber.putNext(value)
                    },
                    error: { error in
                        let attempt = currentAttempt.modify { current in
                            return current + 1
                        }
                        
                        if attempt >= retryCount {
                            subscriber.putError(error)
                        } else {
                            let delay = min(
                                initialDelay * pow(2.0, Double(attempt - 1)),
                                maxDelay
                            )
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                attempt()
                            }
                        }
                    },
                    completed: {
                        subscriber.putCompletion()
                    }
                )
                
                disposable.set(attemptDisposable)
            }
            
            attempt()
            
            return disposable
        }
    }
}
