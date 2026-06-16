# macOS development
- Don't use xcode directly to develop
- Use pure swift 5.8 code to make the app. No interface builder. No SwiftUI.
- Aim for compact code. Within methods, don't have groups of statements separated with newlines. No inline comments for simple code. Instead, split statements into sub-methods.
- Use guard closes as much as possible to separate the happy-path under them
- Organize source files into folders. Folders should group files that change together, at the same pace (e.g. one feature)
- When possible, follow the triad pattern: specs in *Specs.md, unit-tests in *Tests.swift, and *swift for the implementation. Document features and their edge-cases this way
- Favor low latency and responsiveness. Reuse objects, avoid wasting memory or I/O. Use observer APIs; don't poll.

# Workflow
- Copy commands from ai/build.sh and run them, to confirm compilation works after you're done with implementing a change

# License / Keychain invariant
- The app's Developer ID, TeamID, and bundle ID must remain stable across builds. Keychain items are tied to the code signature; changing any of these orphans every user's stored license key and forces mass re-activation. If a rotation is unavoidable, plan a migration first (e.g., a backup-restore handler, or `kSecAttrAccessGroup` with a stable group identifier).
- Do not introduce legacy `SecKeychain*` API or `kSecAccessControl` (biometric/PIN gating) into license code — both can trigger Keychain password prompts, which is bad UX for license activation.
