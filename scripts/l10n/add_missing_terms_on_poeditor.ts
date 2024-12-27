import {L10n} from '../utils/l10n'
import {Poeditor, Term} from "../utils/poeditor";

function compareLocalAndRemote(localTerms: Term[], remoteTerms: Term[]): Term[] {
    const result: Term[] = []
    for (const term of localTerms) {
        const matchingTerm = remoteTerms.some(x => x.term === term.term)
        if (!matchingTerm) {
            result.push({
                term: term.term,
                context: term.new_context,
            })
        }
    }
    return result
}

async function main(): Promise<void> {
    const localTerms = L10n.localTermsFromLocalizationFile(true)
    const remoteTerms = await Poeditor.downloadTerms()
    const termsToAdd = compareLocalAndRemote(localTerms, remoteTerms)
    console.log('Terms to add:', termsToAdd)
    if (termsToAdd.length > 0) {
        let response = await Poeditor.addTerms(termsToAdd)
        console.log(response)
    }
}

main()
