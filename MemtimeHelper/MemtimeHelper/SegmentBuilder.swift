import Foundation

/// Turns one-second activity samples into closed segments.
/// Pure logic: no clock and no I/O. Rule numbers match the design spec
/// (TimesheetHelper docs/superpowers/specs/2026-10-05-native-capture-design.md).
struct SegmentBuilder {
    static let idleThreshold: Int64 = 300
    static let carryForwardLimit: Int64 = 60
    static let maxSampleGap: Int64 = 10
    static let browserBundleIDs: Set<String> = ["com.microsoft.edgemac", "com.apple.Safari"]

    private struct Extraction {
        let title: String
        let enricher: String
        let at: Int64
    }

    /// The segment in progress. The engine checkpoints it every 30 s.
    private(set) var open: CapturedSegment?
    private var lastSampleTime: Int64?
    /// The earliest time a new segment may start, so segments never overlap.
    private var floor: Int64?
    private var lastExtraction: [String: Extraction] = [:]

    mutating func ingest(_ s: ActivitySample) -> [CapturedSegment] {
        var closed: [CapturedSegment] = []

        // Rules 6 and 7: a long gap or a backwards clock ends the open segment
        // at the last sample. This does not depend on sleep notifications.
        if let last = lastSampleTime, s.time < last || s.time - last > Self.maxSampleGap {
            closed += close(at: last)
            raiseFloor(to: s.time)
        }
        lastSampleTime = s.time

        // Rule 9: no segment while the screen is locked.
        if s.isLocked {
            closed += close(at: s.time)
            raiseFloor(to: s.time)
            return closed
        }

        let lastInput = s.time - s.idleSeconds

        // Rules 2 and 3: idle time becomes an offline segment.
        if s.idleSeconds >= Self.idleThreshold {
            if let current = open, current.type == .offline {
                open?.end = max(current.start, s.time)
            } else {
                closed += close(at: lastInput)
                let start = max(lastInput, floor ?? lastInput)
                open = CapturedSegment(start: start, end: max(start, s.time), type: .offline, program: nil,
                                       title: nil, path: nil, rawTitle: nil, enricher: nil)
            }
            return closed
        }

        // Rule 3: input resumed, so the offline segment ends at the first input.
        var startAt = max(s.time, floor ?? s.time)
        if open?.type == .offline {
            closed += close(at: lastInput)
            startAt = max(lastInput, floor ?? lastInput)
        }

        guard let program = s.bundleID else {
            closed += close(at: s.time)
            return closed
        }

        // Rule 1: a change of type, program, title or path starts a new segment.
        let next = describe(s, program: program)
        if let current = open, current.type == next.type, current.program == next.program,
           current.title == next.title, current.path == next.path {
            open?.end = max(current.start, s.time)
        } else {
            closed += close(at: startAt)
            var segment = next
            segment.start = startAt
            segment.end = max(startAt, s.time)
            open = segment
        }
        return closed
    }

    /// Rule 8: sleep, screen lock and user switch end the open segment at the event time.
    mutating func interrupt(at time: Int64) -> [CapturedSegment] {
        let closed = close(at: time)
        raiseFloor(to: time)
        return closed
    }

    /// The fields of the segment this sample belongs to. `start` and `end` are set by the caller.
    private mutating func describe(_ s: ActivitySample, program: String) -> CapturedSegment {
        if Self.browserBundleIDs.contains(program) {
            return CapturedSegment(start: 0, end: 0, type: .browser, program: program,
                                   title: s.tabTitle ?? s.windowTitle, path: s.url,
                                   rawTitle: s.windowTitle, enricher: nil)
        }
        var title = s.windowTitle
        var enricher: String? = nil
        if let name = s.enricherName {
            if let extracted = s.extractedTitle {
                title = extracted
                enricher = name
                lastExtraction[program] = Extraction(title: extracted, enricher: name, at: s.time)
            } else if let previous = lastExtraction[program],
                      s.time - previous.at <= Self.carryForwardLimit {
                // Rule 4: a short run of failed reads keeps the last good title.
                title = previous.title
                enricher = previous.enricher
            }
            // Rule 5: past the limit, the window title applies and `enricher` stays nil.
        }
        return CapturedSegment(start: 0, end: 0, type: .app, program: program, title: title,
                               path: nil, rawTitle: s.windowTitle, enricher: enricher)
    }

    /// The floor only moves forward, so a backwards clock cannot pull it back.
    private mutating func raiseFloor(to time: Int64) {
        floor = max(floor ?? time, time)
    }

    /// Ends the open segment at `time`. A zero-length segment is dropped.
    private mutating func close(at time: Int64) -> [CapturedSegment] {
        guard var segment = open else { return [] }
        open = nil
        segment.end = max(segment.start, time)
        raiseFloor(to: segment.end)
        return segment.end > segment.start ? [segment] : []
    }
}
