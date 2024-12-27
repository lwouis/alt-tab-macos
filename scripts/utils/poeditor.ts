export class Poeditor {
    private static readonly baseUrl = 'https://api.poeditor.com/v2/'
    private static readonly projectId = '316051'
    private static readonly apiKey = process.env.API_KEY ?? throwError('API_KEY is required')

    static async downloadTerms(): Promise<Term[]> {
        return await Poeditor.makeCall('terms/list', [])
            .then(response => response.result.terms)
    }

    static async updateTerms(terms: Term[]): Promise<any> {
        return await Poeditor.makeCall('terms/update', [['data', JSON.stringify(terms)]])
    }

    static async addTerms(terms: Term[]): Promise<any> {
        return await Poeditor.makeCall('terms/add', [['data', JSON.stringify(terms)]])
    }

    private static async makeCall(apiPath: string, params: [string, any][]): Promise<any> {
        const body = new FormData()
        body.append('api_token', Poeditor.apiKey)
        body.append('id', Poeditor.projectId)
        for (const param of params) {
            body.append(param[0], param[1])
        }
        return await fetch(Poeditor.baseUrl + apiPath, {
            method: 'POST',
            body: body,
        })
            .then(async (response) => {
                let json = await response.json();
                // console.log(json)
                return json;
            })
    }
}

export interface Term {
    term: string
    context?: string
    new_context?: string
    tags?: string[]
}

function throwError(message: string): never {
    throw new Error(message)
}
