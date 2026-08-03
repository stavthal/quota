import Foundation

public actor RefreshScheduler {
    public private(set) var currentInterval: TimeInterval
    private let baseInterval: TimeInterval
    private let maxInterval: TimeInterval
    private var task: Task<Void, Never>?

    public init(baseInterval: TimeInterval = 300, maxInterval: TimeInterval = 1800) {
        self.baseInterval = baseInterval
        self.currentInterval = baseInterval
        self.maxInterval = maxInterval
    }

    public func start(tick: @escaping @Sendable () async throws -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                do {
                    try await tick()
                    await self.resetInterval()
                } catch {
                    await self.backoff()
                }
                let sleepFor = await self.currentInterval
                try? await Task.sleep(for: .seconds(sleepFor))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func resetInterval() {
        currentInterval = baseInterval
    }

    public func backoff() {
        currentInterval = min(currentInterval * 2, maxInterval)
    }
}
