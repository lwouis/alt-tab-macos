import {readFileSync, writeFileSync, existsSync} from 'fs'
import * as path from 'path'

const SOURCE_PATH = 'resources/l10n/Localizable.strings'
const L10N_DIR = 'resources/l10n'

interface SourceEntry { comment: string; key: string; value: string }

function parseSource(): SourceEntry[] {
    const text = readFileSync(SOURCE_PATH, 'utf8')
    const re = /\/\*\s*([\s\S]+?)\s*\*\/\s*"([\s\S]+?)"\s*=\s*"([\s\S]+?)"\s*;/g
    const out: SourceEntry[] = []
    let m
    while ((m = re.exec(text)) !== null) {
        out.push({comment: m[1], key: m[2], value: m[3]})
    }
    if (out.length === 0) throw new Error(`No source entries parsed from ${SOURCE_PATH}`)
    return out
}

function parseTarget(filePath: string): Map<string, string> {
    const map = new Map<string, string>()
    if (!existsSync(filePath)) return map
    const text = readFileSync(filePath, 'utf8')
    const re = /"([\s\S]+?)"\s*=\s*"([\s\S]+?)"\s*;/g
    let m
    while ((m = re.exec(text)) !== null) {
        map.set(m[1], m[2])
    }
    return map
}

function normalizedSpecs(s: string): string[] {
    const tokens: string[] = []
    const fmt = s.match(/%(?:\d+\$)?[@d]/g)
    if (fmt) tokens.push(...fmt.map(f => f.replace(/^%\d+\$/, '%')))
    const nl = s.match(/\\n/g); if (nl) tokens.push(...nl)
    const tab = s.match(/\\t/g); if (tab) tokens.push(...tab)
    return tokens.sort()
}

function specsEqual(a: string[], b: string[]): boolean {
    if (a.length !== b.length) return false
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
}

function writeTarget(filePath: string, source: SourceEntry[], merged: Map<string, string>): void {
    const lines: string[] = []
    for (const e of source) {
        const t = merged.get(e.key)
        if (t === undefined) continue
        lines.push(`"${e.key}" = "${t}";`)
    }
    writeFileSync(filePath, lines.join('\n') + '\n')
}

function main(): void {
    const batchPath = process.argv[2]
    if (!batchPath) {
        console.error('Usage: ts-node apply_translations.ts <batch.json>')
        console.error('  batch.json shape: { "<lang>": { "<key>": "<translation>", ... } }')
        console.error('  Always rewrites en.lproj/Localizable.strings as a 1:1 copy of the source.')
        process.exit(1)
    }

    const source = parseSource()
    const srcValueByKey = new Map(source.map(e => [e.key, e.value]))
    const batch: Record<string, Record<string, string>> = JSON.parse(readFileSync(batchPath, 'utf8'))

    // Always mirror source keys into en.lproj. Use key as value so en.lproj
    // is symmetric (key == value), even when genstrings rewrote the source
    // value with positional specifiers like "%1$@" / "%2$@".
    const enPath = path.join(L10N_DIR, 'en.lproj', 'Localizable.strings')
    const enMerged = new Map(source.map(e => [e.key, e.key]))
    writeTarget(enPath, source, enMerged)
    console.log(`en: synced ${enMerged.size} entries from source`)

    let totalMerged = 0
    let totalRejected = 0
    const errors: string[] = []

    for (const [lang, translations] of Object.entries(batch)) {
        if (lang === 'en') {
            console.log(`en: skipped (auto-synced from source)`)
            continue
        }
        const targetPath = path.join(L10N_DIR, `${lang}.lproj`, 'Localizable.strings')
        const existing = parseTarget(targetPath)
        let merged = 0
        let rejected = 0
        for (const [key, translation] of Object.entries(translations)) {
            const srcValue = srcValueByKey.get(key)
            if (srcValue === undefined) {
                errors.push(`${lang}: key not in source: ${JSON.stringify(key)}`)
                rejected++
                continue
            }
            const srcSpecs = normalizedSpecs(srcValue)
            const tgtSpecs = normalizedSpecs(translation)
            if (!specsEqual(srcSpecs, tgtSpecs)) {
                errors.push(
                    `${lang}: format-specifier mismatch for ${JSON.stringify(key)}\n` +
                    `    src=${JSON.stringify(srcSpecs)} tgt=${JSON.stringify(tgtSpecs)}\n` +
                    `    translation: ${JSON.stringify(translation)}`
                )
                rejected++
                continue
            }
            existing.set(key, translation)
            merged++
        }
        writeTarget(targetPath, source, existing)
        console.log(`${lang}: merged ${merged}, rejected ${rejected}, total ${existing.size}`)
        totalMerged += merged
        totalRejected += rejected
    }

    if (errors.length) {
        console.error(`\n${errors.length} error(s):`)
        for (const e of errors) console.error(`  ${e}`)
    }
    console.log(`\nTotal: merged ${totalMerged}, rejected ${totalRejected}`)
    if (totalRejected > 0) process.exit(2)
}

main()
