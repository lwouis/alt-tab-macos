---
name: audit-specs-tests
description: Audit the AltTab test suite for spec/test/code consistency. For every co-located triad in `src/` (`Foo.swift` + `FooSpecs.md` + `FooTests.swift`), it cross-checks that each XCTest method has a matching scenario line in the spec and vice-versa, flags drift between a scenario's description and the test's doc-comment, and reports orphan tests, orphan scenarios, and unpaired files. Use after adding or editing any `*Tests.swift` / `*Specs.md`, before committing a test change, or to get an overall health check of the suite.
---

# /audit-specs-tests

## Project context

AltTab co-locates tests and a living spec next to the source they cover. The convention (see the plan in `.claude/plans/` and `src/pro/license/` as a worked example) is a **triad** per concept:

```
src/<feature>/
├── Foo.swift          # production / kernel (app target, or app+test for kernels)
├── FooSpecs.md        # the living spec (not compiled)
└── FooTests.swift     # XCTest (unit-tests target only)
```

The spec is **documentation tied 1:1 to the test methods**. Its `## Test scenarios` section lists every test, grouped, as:

```markdown
### A. <Group name>
- **testAFooDoesBar** — one-line description of what it pins.
```

This skill's job is to keep the three in sync: every `func test…` ⇔ exactly one `- **test…** —` spec line, descriptions roughly agree, and no triad is missing a leg.

## What counts as a triad

Pair by base name in the **same folder**: `<Base>Tests.swift` ⇔ `<Base>Specs.md`. A `<Base>.swift` (or a kernel like `SelectionResolver.swift`, `SearchTestable.swift`) in the folder is the code under test, but a spec may legitimately cover several classes (e.g. `LicenseManagerSpecs.md` documents `Clock`/`Keychain`/`LicenseAPI` too) — so a missing same-name `.swift` is a note, not an error.

## Workflow

1. **Enumerate.** Find all test and spec files:
   ```sh
   find src -name '*Tests.swift' | sort
   find src -name '*Specs.md' | sort
   ```
   Also list any test files still under `unit-tests/` and flag them as **not yet migrated** (the target end-state is zero test files outside `src/`).

2. **For each `*Tests.swift`, extract the test methods and their doc-comments.** Test names:
   ```sh
   grep -nE '^\s*func test[A-Za-z0-9_]+\(' src/<path>/FooTests.swift
   ```
   For each, capture the immediately-preceding `///` or `//` comment lines (the test's intent) and the enclosing `// MARK: -` group. Note methods wrapped in `#if DEBUG`.

3. **For each `*Specs.md`, parse the scenario index.** In the `## Test scenarios` section, collect every `### <Group>` heading and every `- **testName** — description` bullet. Build the set of spec-listed test names and their descriptions.

4. **Cross-check each triad and classify findings:**
   - **Orphan test** — `func testX` exists but no `- **testX** —` line in the spec. (Most common drift; spec is stale.)
   - **Orphan scenario** — spec lists `testX` but no `func testX` in the suite. (Test deleted/renamed; spec stale.)
   - **Group mismatch** — a test's `// MARK:` group and its spec `###` group disagree (readability drift, not fatal).
   - **Description drift** — the spec bullet and the test's doc-comment describe materially different behavior. Judge semantically, don't string-match; only flag real divergence.
   - **Unpaired file** — a `*Tests.swift` with no `*Specs.md` (or vice-versa).

5. **Lighter code check (kernels only).** For decision-kernel files (`*Testable.swift`, `*Resolver.swift`), list `public`/`static` entry-point functions and `enum … Decision` cases, and flag any with no scenario referencing them — a hint that a branch is undocumented/untested. Skip this for AppKit-coupled production files (intentionally not unit-tested here).

6. **Optionally repair.** If asked, regenerate a spec's `## Test scenarios` section from the live test methods + their doc-comments (preserving the existing `### Group` order where it matches `// MARK:` sections). Never invent behavior — only restate what the test asserts. Do not edit `*Tests.swift` from this skill.

## Reporting

- A per-triad status table: `folder/Base` · #tests · #scenarios · status (✅ in sync / ⚠️ drift / ❌ unpaired).
- A punch list grouped by finding type (orphan tests, orphan scenarios, description drift, unpaired, undocumented kernel branches), each with the file + line.
- The count of test files still outside `src/` (migration progress).
- If nothing is wrong, say so plainly. Then offer to fix the drift (regenerate stale spec scenario indexes) and list exactly which files would change.
