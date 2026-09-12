# macOS development
- Don't use xcode directly to develop
- Use pure swift 5.8 code to make the app. No interface builder. No SwiftUI.
- Aim for compact code. Within methods, don't have groups of statements separated with newlines. No inline comments for simple code. Instead, split statements into sub-methods.
- Use guard closes as much as possible to separate the happy-path under them
- Organize source files into folders. Folders should group files that change together, at the same pace (e.g. one feature)
- When possible, follow the triad pattern: specs in *Specs.md, unit-tests in *Tests.swift, and *swift for the implementation. Document features and their edge-cases this way
- Favor low latency and responsiveness. Reuse objects, avoid wasting memory or I/O. Use observer APIs; don't poll.

# Main-thread IPC
Ordinary AppKit calls can be a synchronous XPC round trip, so they can hang for as long as the other process takes. `searchField.stringValue = ""` froze a user's main thread for 3.0s (#5981): it resigned first responder, which deactivates the system text-input context, which timed out. Assume any AppKit call that changes first responder, orders a window, or resizes one talks to another process.
- Everything under `NSResponder` and `NSCell` (so `NSWindow`, `NSView`, `NSControl`, `NSTextField`, `NSApplication`) plus `NSTextInputContext` is main-thread-only, and AppKit asserts on it at runtime. For those the levers are ordering and deferral, not dispatch: the three off-main schedulers (`AXCallScheduler`, `CGSCallScheduler`, `ProcessCallScheduler`) can't take them.
- `NSWorkspace` and `NSRunningApplication` are the documented exception: their headers state they are thread safe, so LaunchServices reads (`runningApplications`, `frontmostApplication`, `bundleURL`, `icon`, `activate`) may run off-main, and `Application.fetchAppIcon` already relies on that. Don't "fix" them back onto main. `src/main-thread-ipc.md` has the audited call sites and the evidence for both halves of this.
- On the latency-critical paths (summoning, a keystroke while cycling or searching, dismissal with focus), nothing that can stall may run before the work the user is waiting for. Put the visible work first; put the bookkeeping after it.
- A CoreAnimation transaction commits when the runloop turn ENDS. Setting `alphaValue` or calling `orderOut` does not reach the screen before that, so blocking later in the same turn keeps the old frame up. Defer with `DispatchQueue.main.async` and re-check the state in the block.
- `MainThreadStall.step()` at the top of a main-thread function names it in the log when it runs long. Use it to measure rather than guessing; temporarily lower `thresholdInMs` and add marks around single statements to attribute a cost.

# Comments
A wrong comment costs several times more than a missing one, for humans and agents alike. So write for low drift, not for low line count. A correct, non-obvious comment can be as long as it needs to be.
- Comment what the code cannot show: OS/API behaviour (macOS, CGS, SkyLight, AppKit), measured timings, private-API notes, invariants, and why a guard that looks removable isn't. Prefer measured evidence over recollection.
- Don't comment what the code already says. Don't narrate history: no "this used to be X", no reverted approaches, no commentary on earlier comments. If a past bug is the reason a constraint exists, name the test that pins it instead.
- State each rule once, at the widest scope it applies to. Restating it further down is what makes two copies drift apart.
- One intent per comment, and keep it short. Split a paragraph that mixes a rule, its history, and an aside.
- When you change code, re-read the comments around it. Updating them is part of the change, not a follow-up.
- Run `/rework-comments` to audit or rework comments across a file, a folder, or all of `src/`.

# Workflow
- Copy commands from ai/build.sh and run them, to confirm compilation works after you're done with implementing a change
- Run the unit tests with ai/test.sh. Don't use scripts/run_tests.sh: that's the CI entrypoint and its Release config rebuilds the whole test target on every edit (34s vs 1.3s)
- In a git worktree, copy `config/local.xcconfig` over from the main checkout before building. It's gitignored, so a fresh worktree doesn't have it, and `debug.xcconfig` / `release.xcconfig` `#include?` it. Without it the build dies at CodeSign ("no identity found") on a dependency framework, BEFORE the app target's own Swift compile — so it looks like the code compiled when nothing of `src/` was checked. `ai/test.sh` doesn't cover that either: the `unit-tests` target has its own source list and never builds the app target
- Git commit messages must respect our pre-hook conventions, and must be clear and high-level, written for end-users (changelog)

# License / Keychain invariant
- The app's Developer ID, TeamID, and bundle ID must remain stable across builds. Keychain items are tied to the code signature; changing any of these orphans every user's stored license key and forces mass re-activation. If a rotation is unavoidable, plan a migration first (e.g., a backup-restore handler, or `kSecAttrAccessGroup` with a stable group identifier).
- Do not introduce legacy `SecKeychain*` API or `kSecAccessControl` (biometric/PIN gating) into license code — both can trigger Keychain password prompts, which is bad UX for license activation.
