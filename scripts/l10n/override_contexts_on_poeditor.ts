import {L10n} from "../utils/l10n"
import {Poeditor, Term} from "../utils/poeditor";

function compareLocalAndRemote(localTerms: Term[], remoteTerms: Term[]): Term[] {
    let result = []
    for (const localTerm of localTerms) {
        let matchingTerm = remoteTerms.find(x => x.term === localTerm.term)
        if (matchingTerm === undefined) {
            throw `term ${localTerm.term} doesn't exist on poeditor`
        }
        if (localTerm.new_context !== matchingTerm.context) {
            result.push({
                term: localTerm.term,
                new_context: localTerm.new_context,
                context: matchingTerm.context
            })
        }
    }
    return result
}

async function main(): Promise<void> {
    const localTerms = L10n.localTermsFromLocalizationFile(true)
    const remoteTerms = await Poeditor.downloadTerms()
    const termsWithChanges = compareLocalAndRemote(localTerms, remoteTerms)
    console.log('Terms to update:', termsWithChanges)
    if (termsWithChanges.length > 0) {
        let response = await Poeditor.updateTerms(termsWithChanges)
        console.log(response)
    }
}

main()
