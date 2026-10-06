@preconcurrency import ApplicationServices
import AppKit

@MainActor
enum EventTargetResolver {
    static func processIdentifier(for event: CGEvent) -> pid_t? {
        guard let processIdentifier = pid_t(exactly: event.getIntegerValueField(.eventTargetUnixProcessID)),
              processIdentifier > 0 else {
            return nil
        }
        return processIdentifier
    }

    static func bundleIdentifier(for processIdentifier: pid_t) -> String? {
        NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    }

    static func bundleIdentifier(for event: CGEvent) -> String? {
        guard let processIdentifier = processIdentifier(for: event) else { return nil }
        return bundleIdentifier(for: processIdentifier)
    }
}
