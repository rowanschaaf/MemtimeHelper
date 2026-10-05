import AppKit
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "CaptureEngine")

/// What the engine needs from the store. CaptureStore conforms; tests use a fake.
protocol CaptureWriting: AnyObject {
    func insert(_ segment: CapturedSegment) throws
    func checkpoint(_ segment: CapturedSegment?) throws
    func recoverCheckpoint() throws -> CapturedSegment?
}

extension CaptureStore: CaptureWriting {}

/// Samples once a second and writes closed segments to the capture store.
/// Runs alongside WorkspaceObserver, which still writes extracted titles into Memtime.
@MainActor
final class CaptureEngine {
    static let checkpointInterval = 30
    /// More than one day of segments at one per second.
    static let maxPending = 86_400

    private let sampler: ActivitySampler
    private let store: CaptureWriting
    private var builder = SegmentBuilder()
    private(set) var pending: [CapturedSegment] = []
    private var ticks = 0
    private var writeFailing = false
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init(sampler: ActivitySampler, store: CaptureWriting) {
        self.sampler = sampler
        self.store = store
    }

    func start() {
        do {
            if let recovered = try store.recoverCheckpoint() {
                logger.notice("Recovered open segment \(recovered.start)–\(recovered.end)")
            }
        } catch {
            logger.error("Checkpoint recovery failed: \(String(describing: error), privacy: .public)")
        }
        // Common modes, so the timer keeps firing while the menu-bar menu is open.
        // A paused timer would leave a gap over 10 s and split the segment (rule 6).
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeInterruptions()
    }

    func stop(at time: Int64 = Int64(Date().timeIntervalSince1970)) {
        timer?.invalidate()
        timer = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers = []
        distributedObservers = []
        interrupt(at: time)
    }

    func tick() {
        write(builder.ingest(sampler.sample()))
        ticks += 1
        // With nothing open, a checkpoint(nil) would delete the only durable copy
        // of a closed segment still waiting in `pending`.
        if ticks % Self.checkpointInterval == 0, builder.open != nil || pending.isEmpty {
            do {
                try store.checkpoint(builder.open)
            } catch {
                logger.error("Checkpoint failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Rule 8: sleep, screen lock and user switch.
    func interrupt(at time: Int64) {
        write(builder.interrupt(at: time))
    }

    /// Writes new and queued segments in order. A failure keeps them queued and
    /// the next tick retries; the app never stops capture because a write failed.
    private func write(_ closed: [CapturedSegment]) {
        pending += closed
        var inserted = false
        while let next = pending.first {
            do {
                try store.insert(next)
                pending.removeFirst()
                inserted = true
                if writeFailing {
                    writeFailing = false
                    logger.notice("Segment writes recovered")
                }
            } catch {
                if !writeFailing {
                    writeFailing = true
                    logger.error("Segment write failed; queueing: \(String(describing: error), privacy: .public)")
                }
                break
            }
        }
        // insert() deletes the checkpoint row. If it ran while a later segment was
        // open, that segment's checkpoint went with it, so write it again.
        if inserted, let open = builder.open {
            do {
                try store.checkpoint(open)
            } catch {
                logger.error("Checkpoint failed: \(String(describing: error), privacy: .public)")
            }
        }
        if pending.count > Self.maxPending {
            let dropped = pending.count - Self.maxPending
            pending.removeFirst(dropped)
            logger.fault("Dropped \(dropped) queued segments after a day of write failures")
        }
    }

    private func observeInterruptions() {
        let names = [NSWorkspace.willSleepNotification,
                     NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification]
        for name in names {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupt(at: Int64(Date().timeIntervalSince1970)) }
            })
        }
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.interrupt(at: Int64(Date().timeIntervalSince1970)) }
        })
    }
}
