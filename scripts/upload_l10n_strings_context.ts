import {readFile} from 'fs/promises'

const projectId = '316051'
const apiKey = ''

interface Term {
    term: string
    context?: string
    new_context?: string
}

async function localTermsFromLocalizationFile(): Promise<Term[]> {
    const content = await readFile('resources/l10n/Localizable.strings', 'utf8')
    const termRegex = /\/\*\s*([\s\S]+?)\s*\*\/\s*"(.*?)"\s*=[^;]+;/g;
    let match
    const terms = []
    while ((match = termRegex.exec(content)) !== null) {
        const comment = match[1]
        const term = match[2]
        if (comment !== 'No comment provided by engineer.') {
            terms.push({term: term, new_context: comment})
        }
    }
    if (terms.length === 0) {
        throw 'No terms found.'
    }
    return terms
}

async function remoteTermsFromPoeditor(): Promise<Term[]> {
    const body = new URLSearchParams();
    body.append('api_token', apiKey);
    body.append('id', projectId);
    return await fetch('https://api.poeditor.com/v2/terms/list', {
        method: 'POST',
        body: body.toString(),
        headers: {'Content-type': 'application/x-www-form-urlencoded',},
    })
        .then(async (response) => (await response.json()).result.terms)
}

function compareLocalAndRemote(localTerms: Term[], remoteTerms: Term[]): Term[] {
    let termsWithChanges = []
    for (let i = 0; i < localTerms.length; ++i) {
        let matchingRemoteText = remoteTerms.find(x => x.term === localTerms[i].term)
        if (matchingRemoteText === undefined) {
            throw `term ${localTerms[i].term} doesn't exist on poeditor`
        }
        if (localTerms[i].new_context !== matchingRemoteText.context) {
            termsWithChanges.push({term: localTerms[i].term, new_context: localTerms[i].new_context, context: matchingRemoteText.context})
        }
        localTerms[i].context = matchingRemoteText.context
    }
    return termsWithChanges
}

async function updateTerms(localTerms: Term[]): Promise<any> {
    const body = new URLSearchParams();
    body.append('api_token', apiKey);
    body.append('id', projectId);
    body.append('data', JSON.stringify(localTerms));
    return await fetch('https://api.poeditor.com/v2/terms/update', {
        method: 'POST',
        body: body.toString(),
        headers: {'Content-type': 'application/x-www-form-urlencoded',},
    })
        .then(async (response) => await response.json())
}

async function main(): Promise<void> {
    const localTerms = await localTermsFromLocalizationFile()
    const remoteTerms = await remoteTermsFromPoeditor()
    const termsWithChanges = compareLocalAndRemote(localTerms, remoteTerms)
    console.log('Terms with local changes:', termsWithChanges)
    if (termsWithChanges.length > 0) {
        let response = await updateTerms(termsWithChanges)
        console.log(response)
    }
}

main()
