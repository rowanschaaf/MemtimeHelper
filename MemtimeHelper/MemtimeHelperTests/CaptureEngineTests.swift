import XCTest
@testable import MemtimeHelper

private final class FakeSampler: ActivitySampler {
    var queue: [ActivitySample] = []
    func sample() -> ActivitySample { queue.removeFirst() }
}

private final class FakeWriter: CaptureWriting {
    var inserted: [CapturedSegment] = []
    var checkpoints: [CapturedSegment?] = []
    var failInserts = 0
    var leftover: CapturedSegment?
    var recoverCalls = 0

    func insert(_ segment: CapturedSegment) throws {
        if failInserts > 0 {
            failInserts -= 1
            throw CaptureStoreError.sqlite("disk full")
        }
        inserted.append(segment)
    }
    func checkpoint(_ segment: CapturedSegment?) throws { checkpoints.append(segment) }
    func recoverCheckpoint() throws -> CapturedSegment? { recoverCalls += 1; return leftover }
}

@MainActor
final class CaptureEngineTests: XCTestCase {
    private func sample(_ t: Int64, title: String = "Doc A") -> ActivitySample {
        ActivitySample(time: t, bundleID: "com.example.a", windowTitle: title)
    }

    func test_tick_writesSegmentsThatClose() {
        let sampler = FakeSampler()
        sampler.queue = [sample(100), sample(101), sample(102, title: "Doc B")]
        let writer = FakeWriter()
        let engine = CaptureEngine(sampler: sampler, store: writer)
        for _ in 0..<3 { engine.tick() }
        XCTAssertEqual(writer.inserted.map(\.title), ["Doc A"])
        XCTAssertEqual(writer.inserted.first?.end, 102)
    }

    func test_tick_checkpointsEvery30Ticks() {
        let sampler = FakeSampler()
        sampler.queue = (100..<160).map { sample($0) }
        let writer = FakeWriter()
        let engine = CaptureEngine(sampler: sampler, store: writer)
        for _ in 0..<60 { engine.tick() }
        XCTAssertEqual(writer.checkpoints.count, 2)
        XCTAssertEqual(writer.checkpoints.last??.end, 159)
    }

    func test_writeFailure_queues_thenRetriesOnNextTick() {
        let sampler = FakeSampler()
        sampler.queue = [sample(100), sample(101, title: "Doc B"), sample(102, title: "Doc B")]
        let writer = FakeWriter()
        writer.failInserts = 1
        let engine = CaptureEngine(sampler: sampler, store: writer)
        engine.tick()
        engine.tick()                                   // Doc A closes; the insert fails
        XCTAssertEqual(engine.pending.count, 1)
        XCTAssertEqual(writer.inserted, [])
        engine.tick()                                   // retry succeeds
        XCTAssertEqual(engine.pending, [])
        XCTAssertEqual(writer.inserted.map(\.title), ["Doc A"])
    }

    /// `CaptureStore.insert` deletes the checkpoint row, so a retry that lands
    /// after the open segment was checkpointed must write that checkpoint again.
    func test_successfulRetry_recheckpointsTheOpenSegment() {
        let sampler = FakeSampler()
        sampler.queue = [sample(100), sample(101, title: "Doc B"), sample(102, title: "Doc B")]
        let writer = FakeWriter()
        writer.failInserts = 1
        let engine = CaptureEngine(sampler: sampler, store: writer)
        for _ in 0..<3 { engine.tick() }
        XCTAssertEqual(writer.inserted.map(\.title), ["Doc A"])
        XCTAssertEqual(writer.checkpoints.last??.title, "Doc B")
    }

    /// With no open segment, `checkpoint(nil)` would delete the only durable
    /// copy of the interval still waiting in `pending`.
    func test_checkpointTick_whileLockedWithPendingSegments_keepsTheCheckpoint() {
        let sampler = FakeSampler()
        sampler.queue = [sample(100)] + (101...129).map {
            ActivitySample(time: Int64($0), bundleID: "com.example.a", windowTitle: "Doc A", isLocked: true)
        }
        let writer = FakeWriter()
        writer.failInserts = 1000
        let engine = CaptureEngine(sampler: sampler, store: writer)
        for _ in 0..<30 { engine.tick() }
        XCTAssertTrue(writer.checkpoints.isEmpty)
        XCTAssertEqual(engine.pending.count, 1)
    }

    func test_interrupt_writesTheOpenSegment() {
        let sampler = FakeSampler()
        sampler.queue = [sample(100), sample(101)]
        let writer = FakeWriter()
        let engine = CaptureEngine(sampler: sampler, store: writer)
        engine.tick()
        engine.tick()
        engine.interrupt(at: 101)
        XCTAssertEqual(writer.inserted.map(\.end), [101])
    }

    func test_start_recoversTheCheckpoint() {
        let writer = FakeWriter()
        let engine = CaptureEngine(sampler: FakeSampler(), store: writer)
        engine.start()
        engine.stop(at: 0)
        XCTAssertEqual(writer.recoverCalls, 1)
    }
}

@MainActor
final class CaptureEngineLifecycleTests: XCTestCase {
    func test_startTwiceThenStop_leavesNoLiveTimer() {
        let sampler = FakeSampler()           // empty queue: any tick would crash
        let engine = CaptureEngine(sampler: sampler, store: FakeWriter())
        engine.start()
        engine.start()
        engine.stop(at: 100)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(sampler.queue.isEmpty)  // reaching here means no tick fired
    }
}
