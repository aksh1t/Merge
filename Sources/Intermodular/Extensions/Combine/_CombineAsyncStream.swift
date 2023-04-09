//
// Copyright (c) Vatsal Manot
//

import Combine
import Swift

public class _CombineAsyncStream<Upstream: Publisher>: AsyncSequence {
    public typealias Element = Upstream.Output
    public typealias AsyncIterator = _CombineAsyncStream<Upstream>
    
    private var stream: AsyncThrowingStream<Element, Error>
    private var cancellable: AnyCancellable?
    private lazy var iterator = stream.makeAsyncIterator()
    
    public init(_ upstream: Upstream) {
        stream = .init { _ in }
        cancellable = nil
        stream = .init { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.cancellable?.cancel()
            }
            
            cancellable = upstream
                .handleEvents(
                    receiveCancel: { [weak self] in
                        continuation.finish(throwing: nil)
                        self?.cancellable = nil
                    }
                )
                .sink(receiveCompletion: { [weak self] completion in
                    switch completion {
                        case .failure(let error):
                            continuation.finish(throwing: error)
                        case .finished:
                            continuation.finish(throwing: nil)
                    }
                    self?.cancellable = nil
                }, receiveValue: { value in
                    continuation.yield(value)
                })
        }
    }
    
    public func makeAsyncIterator() -> Self {
        return self
    }
}

extension _CombineAsyncStream: AsyncIteratorProtocol {
    public func next() async throws -> Upstream.Output? {
        return try await iterator.next()
    }
}

extension Publisher where Failure == Never {
    public var stream: AsyncStream<Output> {
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            return values.eraseToStream()
        } else {
            return _CombineAsyncStream(self).eraseToStream()
        }
    }
}

extension Publisher where Failure == Error {
    public var stream: AsyncThrowingStream<Output, Failure> {
        _CombineAsyncStream(self).eraseToThrowingStream()
    }
}
