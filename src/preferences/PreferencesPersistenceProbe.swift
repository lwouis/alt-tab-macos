import Foundation

/// Pure decision layer for "can AltTab actually persist its preferences to disk?".
///
/// AltTab stores prefs via `UserDefaults`/`CFPreferences`, which `cfprefsd` brokers. cfprefsd keeps values
/// in memory and flushes them to `~/Library/Preferences/<suite>.plist` on its own schedule, so a setting can
/// look applied in-process yet never reach disk and silently reset on the next launch (issue #5790). Two
/// concrete, observable conditions guarantee non-persistence on every supported macOS:
///   - the plist is a SYMLINK — dotfile-sync tools (Mackup, chezmoi, …) replace it with a link into a synced
///     folder, and cfprefsd does not persist through a symlinked preferences file;
///   - the plist EXISTS but isn't writable by us — typically owned by `root` after the app was once run via
///     `sudo`, so cfprefsd (running as the user) can't rewrite it.
///
/// The shell (`PreferencesPersistenceCheck`) gathers the filesystem facts with `FileManager`; this kernel
/// turns them into a verdict. It is deliberately FAIL-SAFE: it reports `.broken` only on the two unambiguous
/// conditions above. Anything uncertain — file absent (normal on a fresh install), a writable regular file,
/// or any stat error — is `.ok`, so a healthy or first-launch user is never nagged.
///
/// We intentionally do NOT detect persistence by writing a canary and reading it back: cfprefsd's in-memory
/// cache masks same-launch failures, its disk flush is deferred (can be "seconds later"), and
/// `CFPreferencesAppSynchronize`'s success return is documented-unreliable — none of which can meet the
/// "only fire on 100% clear evidence" bar.
enum PreferencesPersistenceProbe {
    /// Filesystem facts about one suite's backing plist. Primitives only, so this type compiles into the
    /// `unit-tests` target alongside the kernel (no AppKit, no `FileManager`).
    struct SuiteFacts: Equatable {
        let suiteName: String
        /// Absolute path of the suite's plist, included verbatim in the user-facing message.
        let plistPath: String
        /// `lstat` succeeded. True for a symlink even when its target is missing (a dangling Mackup link).
        let exists: Bool
        /// The plist path ITSELF is a symbolic link (not followed).
        let isSymlink: Bool
        /// Whether we can write the file. Only meaningful — and only consulted — when `exists && !isSymlink`.
        let isWritable: Bool
    }

    enum Verdict: Equatable {
        case ok
        /// At least one suite can't persist. The arrays name the offending plist paths so the shell can give
        /// the user a tailored fix (un-sync the symlink vs. restore ownership). At least one is non-empty.
        case broken(symlinkedPaths: [String], unwritablePaths: [String])
    }

    static func verdict(_ facts: [SuiteFacts]) -> Verdict {
        var symlinked = [String]()
        var unwritable = [String]()
        for f in facts {
            guard f.exists else { continue } // absent ⇒ fail-safe OK (no file yet, or transient)
            if f.isSymlink {
                symlinked.append(f.plistPath) // symlink wins; don't also flag writability of the link
                continue
            }
            if !f.isWritable {
                unwritable.append(f.plistPath)
            }
        }
        if symlinked.isEmpty && unwritable.isEmpty {
            return .ok
        }
        return .broken(symlinkedPaths: symlinked, unwritablePaths: unwritable)
    }
}
