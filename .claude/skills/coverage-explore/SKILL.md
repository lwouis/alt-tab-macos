---
name: coverage-explore
description: Measure AltTab test coverage and record it as documentation. Runs the Test scheme with coverage into a throwaway result bundle, parses the per-file/region report, refreshes the per-feature badge atop each `*Specs.md` and the root `src/coverage.md` table, then suggests the highest-value missing tests. These two markdown outputs are the ONLY stored coverage — no lcov/html/xcresult is kept, and routine test runs don't gather coverage. Use to refresh coverage docs, find untested kernel branches, or decide what to test next.
---

# /coverage-explore

## Project context

AltTab follows the **Humble Object** pattern: logic lives in dependency-free **decision kernels**
(`SelectionResolver.swift`, `SearchModeResolver.swift`, the `*Testable.swift` files) compiled into the
`unit-tests` target and tested in isolation; the AppKit layer (windows, views, event taps) is kept thin
and is deliberately *not* unit-tested. So coverage is meaningful **per kernel / per feature-source** —
those should trend to ~100%, every decision branch exercised — and an aggregate app-wide % is not a
goal.

**Coverage is documentation here, not a build artifact.** The only stored coverage is:
1. the per-feature badge (`> **Line coverage:** …`) atop each `*Specs.md`, and
2. the root **`src/coverage.md`** table.

There is intentionally **nothing else**: no lcov, no HTML, no committed `.xcresult`, and coverage is
**not** gathered on routine runs (`scripts/run_tests.sh`, CI, or Xcode) — only when this skill runs it.
(Coverage isn't usefully viewable in IntelliJ, so there's no IDE-integration artifact to maintain.)

## Workflow

1. **Measure into a throwaway bundle** (then delete it — store nothing technical):
   ```sh
   rm -rf /tmp/altcov.xcresult
   set -o pipefail && xcodebuild test \
     -project alt-tab-macos.xcodeproj -scheme Test -configuration Release \
     -enableCodeCoverage YES -resultBundlePath /tmp/altcov.xcresult | scripts/xcbeautify
   ```
   If the build is red, stop and report — coverage on a failing suite is meaningless.

2. **Parse** `xcrun xccov view --report --json /tmp/altcov.xcresult`. Each `targets[].files[]` has
   `path`, `lineCoverage`, `coveredLines`, `executableLines`, `functions[]`. For line-by-line counts of
   one file while investigating a gap: `xcrun xccov view --file <abs-path> /tmp/altcov.xcresult`.

3. **Refresh `src/coverage.md`.** Rewrite the table with every `src/` file (excluding `*Tests.swift`)
   that the test target compiles, sorted worst-coverage-first, as `| NN% (cov/exec) | \`path\` |`.
   Keep the header note explaining the Humble-Object scope and that this + the badges are the only
   stored coverage. Update the "updated" date.

4. **Offer to refresh the per-spec badges.** For each `<Base>Specs.md` whose `<Base>.swift` (or kernel)
   is in the report, propose updating its `> **Line coverage:** …` line with the new % + today's date.
   Ask first; only apply the ones the user accepts. Keep honest notes where a file is intentionally
   partial (e.g. `PreferencesMigrations.swift`).

5. **Rank gaps & suggest tests.** For kernels below 100%, list the uncovered functions/regions, map each
   to the behavior it represents (read the source), and write ready-to-paste additions: a
   `- **testGroupScenario** — …` spec line + a short XCTest stub in that suite's builder style. Don't add
   tests automatically unless asked.

6. **Clean up:** `rm -rf /tmp/altcov.xcresult`. Leave no technical coverage files in the tree.

## Reporting

- Headline: a small ascending table of kernel `lineCoverage`, and the delta vs the previous `src/coverage.md`.
- Ranked gap list: file → uncovered function/branch → the behavior it represents.
- Suggested scenarios (spec lines + test stubs) for the top gaps.
- State exactly what was rewritten (`src/coverage.md`, which badges). Flag files that are partial *by
  design* (AppKit glue, excluded migrations) so a low number isn't mistaken for a problem.
