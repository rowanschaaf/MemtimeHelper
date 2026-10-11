import ServiceManagement

/// Decides when the app registers itself as a login item.
enum LoginItem {
    /// `.notRegistered` is a first launch. `.notFound` is what macOS reports
    /// after the item is removed in System Settings; without registering again
    /// the app silently stops starting at login. `.requiresApproval` means the
    /// user switched the item off, so the app leaves that choice alone.
    static func shouldRegister(_ status: SMAppService.Status) -> Bool {
        status == .notRegistered || status == .notFound
    }
}
