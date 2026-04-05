import AppKit
import Darwin

// Replacement for the LetsMove pod (~600 lines of Obj-C, 436 KB framework).
// Preserves the user-visible behaviour:
//  - Skip if user opted out previously (same UserDefaults key for cross-version continuity)
//  - Skip if already in any Applications folder (and not nested in another .app)
//  - Detect running instance at destination → switch to it and quit self
//  - NSAlert with suppression checkbox
//  - Copy bundle, strip com.apple.quarantine xattr, relaunch
//  - If launched from a disk image: detach DMG after relaunch
// Intentionally drops:
//  - AuthorizationExecuteWithPrivileges path (deprecated since 10.7; alt-tab users
//    drag from DMG → /Applications is writable in the common case)
//  - AppleScript trash fallback (alt-tab is not subject to app translocation since it
//    requires Accessibility permission, which can't be granted to translocated apps)
enum MoveToApplicationsFolder {
    // Same key as LetsMove so users who already opted out stay opted out across the migration.
    private static let suppressKey = "moveToApplicationsFolderAlertSuppress"
    private(set) static var inProgress = false

    static func promptIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { promptIfNeeded() }
            return
        }
        if UserDefaults.standard.bool(forKey: suppressKey) { return }
        let bundlePath = Bundle.main.bundlePath
        let nested = isNestedInAnotherApp(bundlePath)
        if isInApplicationsFolder(bundlePath) && !nested { return }
        inProgress = true
        defer { inProgress = false }
        let fm = FileManager.default
        let diskImageDevice = containingDiskImageDevice(bundlePath)
        guard let applicationsDir = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .localDomainMask, true).last else { return }
        let bundleName = (bundlePath as NSString).lastPathComponent
        let destinationPath = (applicationsDir as NSString).appendingPathComponent(bundleName)
        // We don't ship the authorized-install path; if /Applications isn't writable, advise manual move.
        let needsAuthorization = !fm.isWritableFile(atPath: applicationsDir)
            || (fm.fileExists(atPath: destinationPath) && !fm.isWritableFile(atPath: destinationPath))
        if needsAuthorization {
            showCouldNotMoveAlert(needsAdmin: true)
            return
        }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Move to Applications folder?", comment: "LetsMove replacement alert")
        var info = NSLocalizedString("I can move myself to the Applications folder if you'd like.", comment: "LetsMove replacement alert")
        if isInDownloadsFolder(bundlePath) {
            info += " " + NSLocalizedString("This will keep your Downloads folder uncluttered.", comment: "LetsMove replacement alert")
        }
        alert.informativeText = info
        alert.addButton(withTitle: NSLocalizedString("Move to Applications Folder", comment: "LetsMove replacement alert"))
        let cancel = alert.addButton(withTitle: NSLocalizedString("Do Not Move", comment: "LetsMove replacement alert"))
        cancel.keyEquivalent = "\u{1b}" // Escape
        alert.showsSuppressionButton = true
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: suppressKey)
            }
            return
        }
        // If a copy already exists in /Applications and is running, switch to it and quit self.
        if fm.fileExists(atPath: destinationPath) {
            if isApplicationRunning(at: destinationPath) {
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = [destinationPath]
                try? task.run()
                task.waitUntilExit()
                exit(0)
            }
            do {
                try fm.trashItem(at: URL(fileURLWithPath: destinationPath), resultingItemURL: nil)
            } catch {
                showCouldNotMoveAlert(needsAdmin: false)
                return
            }
        }
        do {
            try fm.copyItem(atPath: bundlePath, toPath: destinationPath)
        } catch {
            showCouldNotMoveAlert(needsAdmin: false)
            return
        }
        // Trash the original (best effort — failure is non-fatal, the user still has a working copy in /Applications)
        if !nested && diskImageDevice == nil {
            try? fm.trashItem(at: URL(fileURLWithPath: bundlePath), resultingItemURL: nil)
        }
        relaunch(at: destinationPath, dmgDevice: diskImageDevice)
        exit(0)
    }

    private static func isInApplicationsFolder(_ path: String) -> Bool {
        for appDir in NSSearchPathForDirectoriesInDomains(.applicationDirectory, .allDomainsMask, true) where path.hasPrefix(appDir) {
            return true
        }
        // Catch additional Applications folders on non-system partitions
        return (path as NSString).pathComponents.contains("Applications")
    }

    private static func isInDownloadsFolder(_ path: String) -> Bool {
        for downloadsDir in NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .allDomainsMask, true) where path.hasPrefix(downloadsDir) {
            return true
        }
        return false
    }

    private static func isNestedInAnotherApp(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        return (parent as NSString).pathComponents.contains { ($0 as NSString).pathExtension == "app" }
    }

    private static func isApplicationRunning(at bundlePath: String) -> Bool {
        let standardized = (bundlePath as NSString).standardizingPath
        for running in NSWorkspace.shared.runningApplications {
            if let url = running.bundleURL, (url.path as NSString).standardizingPath == standardized {
                return true
            }
        }
        return false
    }

    // hdiutil info -plist returns mounted images; if our bundle's filesystem matches one of its
    // dev-entries, we're running from a DMG and want to detach it after relaunch.
    private static func containingDiskImageDevice(_ path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        var fs = statfs()
        guard statfs(parent, &fs) == 0 else { return nil }
        if (Int32(fs.f_flags) & MNT_ROOTFS) != 0 { return nil }
        let device = withUnsafeBytes(of: &fs.f_mntfromname) { ptr -> String in
            let raw = ptr.bindMemory(to: CChar.self).baseAddress!
            return String(cString: raw)
        }
        let task = Process()
        task.launchPath = "/usr/bin/hdiutil"
        task.arguments = ["info", "-plist"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = info["images"] as? [[String: Any]] else { return nil }
        for image in images {
            guard let entities = image["system-entities"] as? [[String: Any]] else { continue }
            for entity in entities {
                if let devEntry = entity["dev-entry"] as? String, devEntry == device {
                    return device
                }
            }
        }
        return nil
    }

    private static func relaunch(at destinationPath: String, dmgDevice: String?) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let quoted = shellQuoted(destinationPath)
        // Strip quarantine xattr so the relaunched binary doesn't trigger Gatekeeper's
        // "scary file from internet" prompt.
        let preOpen = "/usr/bin/xattr -d -r com.apple.quarantine \(quoted) 2>/dev/null"
        var script = "(while /bin/kill -0 \(pid) >&/dev/null; do /bin/sleep 0.1; done; \(preOpen); /usr/bin/open \(quoted))"
        if let dmgDevice {
            // 5s grace lets the old PID actually die before unmount; if files are open hdiutil will refuse.
            script += " && (/bin/sleep 5 && /usr/bin/hdiutil detach \(shellQuoted(dmgDevice)) >&/dev/null) &"
        } else {
            script += " &"
        }
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        try? task.run()
    }

    private static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func showCouldNotMoveAlert(needsAdmin: Bool) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Could not move to Applications folder", comment: "LetsMove replacement alert")
        if needsAdmin {
            alert.informativeText = NSLocalizedString("Please drag AltTab into the Applications folder manually.", comment: "LetsMove replacement alert")
        }
        alert.runModal()
    }
}
