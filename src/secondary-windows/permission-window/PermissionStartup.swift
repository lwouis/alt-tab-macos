/// Permission reads and main-thread presentation can finish in different orders. Read live state
/// again inside each queued action; the start action must set the startup latch before launching.
struct PermissionStartup {
    let isComplete: () -> Bool
    let hasStarted: () -> Bool
    let enqueue: (@escaping () -> Void) -> Void
    let start: () -> Void
    let showWindow: () -> Void
    let checkAgain: () -> Void

    func check() {
        if isComplete() {
            enqueue {
                guard !hasStarted() else { return }
                guard isComplete() else {
                    checkAgain()
                    return
                }
                start()
            }
        } else {
            enqueue {
                guard !hasStarted() else { return }
                guard !isComplete() else { return }
                showWindow()
            }
        }
    }
}
