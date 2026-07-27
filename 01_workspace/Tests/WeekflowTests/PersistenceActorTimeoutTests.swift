import Foundation
import Testing
@testable import Weekflow

@Test func syncBridgeTimeoutCancelsQueuedTransactionBeforeItCanWrite() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowActorTimeout-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let actor = PersistenceActor(
        storeURL: folder.appendingPathComponent("Weekflow.store"),
        syncBridgeTimeoutSeconds: 0.02
    )
    let blockerStarted = DispatchSemaphore(value: 0)
    let releaseBlocker = DispatchSemaphore(value: 0)
    let blocker = Task.detached {
        try await actor.performTransaction { _ in
            blockerStarted.signal()
            releaseBlocker.wait()
        }
    }
    let blockerDidStart = await waitForSemaphore(blockerStarted)
    #expect(blockerDidStart)

    let state = PersistenceActorTimeoutState()
    let bridgeFinished = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try actor.runSyncBlocking { _ in
                state.markTransactionRan()
            }
        } catch {
            state.record(error: error)
        }
        bridgeFinished.signal()
    }

    try await Task.sleep(for: .milliseconds(80))
    releaseBlocker.signal()
    let bridgeDidFinish = await waitForSemaphore(bridgeFinished)
    #expect(bridgeDidFinish)
    _ = try await blocker.value

    #expect(state.transactionRan == false)
    guard case .syncBridgeTimedOut? = state.error as? PersistenceActorError else {
        Issue.record("Expected syncBridgeTimedOut, got \(String(describing: state.error))")
        return
    }
}

private func waitForSemaphore(_ semaphore: DispatchSemaphore) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(returning: semaphore.wait(timeout: .now() + 2) == .success)
        }
    }
}

private final class PersistenceActorTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTransactionRan = false
    private var storedError: Error?

    var transactionRan: Bool { lock.withLock { storedTransactionRan } }
    var error: Error? { lock.withLock { storedError } }

    func markTransactionRan() {
        lock.withLock { storedTransactionRan = true }
    }

    func record(error: Error) {
        lock.withLock { storedError = error }
    }
}
