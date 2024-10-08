const fs = require('fs');
const path = require('path');
const glob = require('glob');
const { execFileSync } = require('child_process');

const ignoreFilePath = path.join(__dirname, '..', '.swiftformatignore');
const ignorePatterns = fs.readFileSync(ignoreFilePath, 'utf8')
    .split('\n')
    .map(line => line.trim())  // Remove leading and trailing whitespace
    .filter(line => line && !line.startsWith('#'));  // Filter out empty lines and comments

const files = glob.sync('**/*.swift', { ignore: ignorePatterns });

if (files.length > 0) {
    const commandArgs = process.argv.slice(2).concat(files);
    try {
        execFileSync('swiftformat', commandArgs, { stdio: 'inherit' });
    } catch (error) {
        console.warn('swiftformat did not pass, please execute `npm run format` command to format swift files.');
    }
} else {
    console.log('No Swift files to format.');
}
