import {L10n} from '../utils/l10n'
import {Poeditor, Term} from "../utils/poeditor";

function addContextToTerms(termsWithVersionTags: Term[], remoteTerms: Term[]) {
    const result: Term[] = []
    for (const term of termsWithVersionTags) {
        const matchingTerm = remoteTerms.find(x => x.term === term.term)
        if (matchingTerm) {
            if (matchingTerm.tags?.[0] !== term.tags?.[0] || matchingTerm.tags?.[1] !== term.tags?.[1]) {
                const r: Term = {term: term.term, tags: term.tags};
                if (matchingTerm.context !== '') {
                    r.context = matchingTerm.context
                }
                result.push(r)
            }
        }
    }
    return result
}

async function main(): Promise<void> {
    const localTermsFromGit = await L10n.computeTermsWithTagsFromGit()
    const remoteTerms = await Poeditor.downloadTerms()
    const termsWithChanges = addContextToTerms(localTermsFromGit, remoteTerms)
    console.log('Terms to update:', termsWithChanges)
    if (termsWithChanges.length > 0) {
        let response = await Poeditor.updateTerms(termsWithChanges)
        console.log(response)
    }
}

main()
