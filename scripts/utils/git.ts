import {exec as execWithCallback} from 'child_process'
import {promisify} from "util"

const exec = promisify(execWithCallback)

export class Git {
    static async getVersionTags(): Promise<string[]> {
        // Localizable.strings was introduced in v3.3.0; we filter out tags before that
        const stdout = (await exec(`git tag -l 'v*' --no-merged v3.2.1`, {encoding: 'utf8'})).stdout.trim()
        return stdout.split("\n")
    }

    static async getFileFromTag(tag: string): Promise<string> {
        return (await exec(`git show ${tag}:resources/l10n/Localizable.strings`, {encoding: 'utf8'})).stdout.trim()
    }
}
