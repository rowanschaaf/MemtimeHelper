import Foundation

/// Segment types. The raw values match Memtime's `TTracking.type`, so
/// TimesheetHelper treats both sources the same way.
enum SegmentType: String {
    case app, browser, offline
}

/// One tick of facts from the sampler.
struct ActivitySample: Equatable {
    var time: Int64
    var bundleID: String?
    var windowTitle: String?
    var url: String? = nil
    var tabTitle: String? = nil
    var idleSeconds: Int64 = 0
    /// Name of the extractor registered for this app; nil when the app has none.
    var enricherName: String? = nil
    /// What that extractor returned this tick; nil on a failed read.
    var extractedTitle: String? = nil
    var isLocked: Bool = false
}

/// A span of one activity. `segments` rows are closed; the checkpoint row is open.
struct CapturedSegment: Equatable {
    var start: Int64
    var end: Int64
    var type: SegmentType
    var program: String?
    var title: String?
    var path: String?
    var rawTitle: String?
    var enricher: String?
}
