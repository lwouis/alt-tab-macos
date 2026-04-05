---
name: translate-missing-l10n
description: Translate missing l10n strings for AltTab using Claude's multilingual ability. Refreshes the source `Localizable.strings` from current Swift code, finds keys missing in each `<lang>.lproj/Localizable.strings`, translates them, then writes them back via `scripts/l10n/apply_translations.ts`.
---

# /translate-missing-l10n

## Project context

AltTab is a macOS app that helps switch between windows, similar to the Windows alt-tab experience. The strings to translate are mostly Settings UI — some tooltips, dialogs, and general user guidance.

## Target languages (20)

`de, ja, fr, es, zh-CN, pt-BR, nl, ko, it, pl, ar, zh-HK, vi, tr, sv, th, zh-TW, he, id, ru`

(`en` is the source — handled automatically by the apply step.)

## Translation guidelines

- **Format specifiers must be preserved exactly**: `%@`, `%d`, `%1$@`, `%2$@`, `\n`, `\t`. The number and order of specifiers in the translation must match the source. Positional and unindexed forms are interchangeable (`%@ %@` ≡ `%1$@ %2$@`), but the count must match.
- **Do not translate proper nouns**: "AltTab", "macOS", "Mission Control", "Spaces", "Dock".
- **Do not translate modifier key names**: "Cmd", "Option", "Alt", "Shift", "Ctrl", "Control", "Fn", "Command".
- **Use Apple's official platform terminology** for the target locale where one exists. For example, prefer the term Apple uses in macOS System Settings for that locale ("Réglages" vs "Préférences" in French) over a literal translation.
- **Match the source brevity**. Settings strings are short; the translation should be short too. Prefer concise, idiomatic phrasing over literal grammatical completeness.
- **Match macOS tone**: neutral, direct, no exclamation marks unless the source has them.
- **Comments in the source file are engineer guidance, not user-visible text**. Use them to disambiguate meaning, but never include them in the translation.

## Workflow

1. **Refresh the source.** Run:
   ```sh
   bash scripts/l10n/extract_l10n_strings.sh
   ```
   This regenerates `resources/l10n/Localizable.strings` from the current Swift code via `genstrings`.

2. **Parse the source.** Read `resources/l10n/Localizable.strings`. Each entry has the shape:
   ```
   /* engineer comment */
   "key" = "value";
   ```
   Build the ordered list of `(comment, key, value)` triples. The `value` for the source is usually identical to `key`, but may include positional indices (`%1$@`, `%2$@`) when there are multiple specifiers.

3. **Compute missing keys per language.** For each of the 20 target languages, read `resources/l10n/<lang>.lproj/Localizable.strings`. Each line is `"key" = "translation";`. A key is **missing** if it's present in the source but either (a) absent from the target file, or (b) present with an empty or whitespace-only value. Treat (b) the same as (a) — produce a real translation.

4. **Stop if nothing is missing.** Report and exit.

5. **Translate.** For each language, produce a translation for each missing key, applying the guidelines above. Do not invent keys; only translate keys that appear in the source. Group your work into batches of 5–10 languages per call to keep individual outputs manageable.

6. **Apply each batch.** Write the batch to a fresh file under `/tmp` (not committed) with this shape:
   ```json
   {
     "fr": { "About %@": "À propos de %@", "Quit": "Quitter" },
     "ja": { "About %@": "%@について" }
   }
   ```
   Then run:
   ```sh
   npx ts-node scripts/l10n/apply_translations.ts /tmp/batch-NN.json
   ```
   The helper:
   - Validates format specifiers — translations whose specifier set doesn't match the source value are rejected with a clear error and **not merged**.
   - Always rewrites `en.lproj/Localizable.strings` from source **keys** (each entry written as `"key" = "key";` for symmetry) — no need to include `en` in your batch. This avoids leaking genstrings-rewritten values like `%1$@` into the English file when the original source key uses plain `%@`.
   - Rewrites each `<lang>.lproj/Localizable.strings` using source order: existing translations are preserved, new translations merged in, and keys no longer in the source are pruned.
   - Exits with code `2` if any entries were rejected.

7. **Handle rejections.** If `apply_translations.ts` reports format-specifier mismatches, fix those translations and re-run only the affected language(s) in a follow-up batch. Do not move on while rejections are outstanding.

## Reporting

After the run, report:

- Number of languages processed.
- Total translations produced and merged.
- Any entries you intentionally left untranslated (e.g., the source was already a proper noun) — list them so the user can decide.
- Any format-specifier rejections that required manual fixes.
