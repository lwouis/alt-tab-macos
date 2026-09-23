import Foundation

/// **Parks the notarization ticket while AltTab runs, and puts it back when it quits.**
///
/// `stapler` writes the ticket to `Contents/CodeResources`, the one path the signature does not seal, so moving
/// it changes neither the code signature nor anything tied to it: the Screen Recording grant, the Keychain
/// license items, Gatekeeper's record of the app. The ticket is for Gatekeeper's first look at a downloaded
/// copy, which has already happened by the time AltTab runs.
///
/// It is worth moving because macOS validates AltTab's bundle from disk for every permission check, three per
/// window screenshot, with nothing cached. When a ticket is stapled, that validation also extracts it and
/// registers it with the system again ("Registering stapled ticket with system" in tccd's log). Measured on
/// macOS 27 (M5): ~10ms of a 30ms check at rest; 45ms vs 19ms per check during a 43-window refresh, which took
/// 5.5s stapled and 2.9s parked (#6067).
///
/// It is parked at `Contents/Resources/en.lproj/locversion.plist` because the signature's own resource rules
/// omit that path (`^Resources/.*\.lproj/locversion.plist$`), so the bundle stays valid with the ticket there.
/// Any other new name in the bundle breaks the seal, and then tccd can no longer match AltTab to its grant and
/// macOS asks for Screen Recording again. `.DS_Store` is omitted too, but Finder writes that name. Staying
/// inside the bundle means an update, which replaces the whole bundle, takes the parked ticket with it; a
/// crash or a forced exit leaves it parked, and the next quit restores it.
enum StapledTicket {
    enum Outcome: Equatable {
        case moved
        case nothingToDo
        case failed(Int32)
    }

    /// Serializes the background park with the synchronous restore at quit.
    private static let queue = DispatchQueue(label: "stapled-ticket")

    /// Off main: a rename is cheap, but it is still disk I/O on the launch path.
    static func parkInBackground() {
        queue.async { log("parked", park(Bundle.main.bundleURL)) }
    }

    /// Synchronous, since the process exits right after. Called once captures are drained, so no permission
    /// check of ours can read the bundle while the ticket moves.
    static func restoreBeforeExit() {
        queue.sync { log("restored", restore(Bundle.main.bundleURL)) }
    }

    static func park(_ bundle: URL) -> Outcome {
        move(stapledUrl(bundle), parkedUrl(bundle))
    }

    static func restore(_ bundle: URL) -> Outcome {
        move(parkedUrl(bundle), stapledUrl(bundle))
    }

    static func stapledUrl(_ bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/CodeResources")
    }

    static func parkedUrl(_ bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/Resources/en.lproj/locversion.plist")
    }

    /// Only a file that is a ticket moves, and never over an existing file: `RENAME_EXCL` makes the check and
    /// the rename one atomic step. A missing `en.lproj` is left missing, since creating it would add a language
    /// to the app.
    private static func move(_ from: URL, _ to: URL) -> Outcome {
        guard isTicket(from) else { return .nothingToDo }
        guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) != 0 else { return .moved }
        let error = errno
        return error == EEXIST || error == ENOENT ? .nothingToDo : .failed(error)
    }

    /// Notarization tickets start with the magic `s8ch`.
    private static func isTicket(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data("s8ch".utf8)
    }

    private static func log(_ verb: String, _ outcome: Outcome) {
        switch outcome {
            case .moved: Logger.info { "\(verb) the stapled notarization ticket" }
            case .nothingToDo: break
            case .failed(let error): Logger.info { "could not move the stapled notarization ticket: \(String(cString: strerror(error)))" }
        }
    }
}
