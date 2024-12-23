import {readFileSync} from 'fs'
import {Git} from "./git";
import {Term} from "./poeditor";

export class L10n {
    static async computeTermsWithTagsFromGit(): Promise<Term[]> {
        const versionTags = (await Git.getVersionTags()).toSorted().toReversed()
        let result: Term[] = []
        for (const versionTag of versionTags) {
            const fileContents = await Git.getFileFromTag(versionTag)
            const localTerms = L10n.localTermsFromLocalizationFileContents(fileContents, false)
            for (const localTerm of localTerms) {
                const matchingTerm = result.find(x => x.term === localTerm.term)
                if (matchingTerm === undefined) {
                    result.push(Object.assign({}, localTerm, {tags: ['to_' + versionTag]}))
                } else {
                    matchingTerm.tags![1] = 'from_' + versionTag
                }
            }
        }
        return result
    }
    static localTermsFromLocalizationFile(forContext: Boolean): Term[] {
        const fileContents = readFileSync('resources/l10n/Localizable.strings', 'utf8')
        return L10n.localTermsFromLocalizationFileContents(fileContents, forContext)
    }

    private static localTermsFromLocalizationFileContents(fileContents: string, forContext: Boolean): Term[] {
        const termRegex = /\/\*\s*([\s\S]+?)\s*\*\/\s*"([\s\S]+?)"\s*=[^;]+;/g;
        let match
        const terms = []
        while ((match = termRegex.exec(fileContents)) !== null) {
            const comment = match[1]
            const term = match[2].replace(/\\n/g, '\n') // un-escape newlines
            let newTerm: Term = {term: term}
            if (forContext && comment !== 'No comment provided by engineer.') {
                newTerm.new_context = comment
            }
            terms.push(newTerm)
        }
        if (terms.length === 0) {
            throw 'No terms found.'
        }
        return terms
    }
}
