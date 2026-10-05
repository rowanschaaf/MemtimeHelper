import Foundation

/// Advisory exclusive lock on a file, held for the life of the object.
/// Keeps a second process (a dev build, a test host) from writing the capture store.
final class SingleWriterLock {
    private let fd: Int32

    init?(url: URL) {
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        self.fd = fd
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
