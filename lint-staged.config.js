const micromatch = require('micromatch');

const ignoredFiles = [
    '**/PrivateApis.swift'
];

module.exports = {
    '*.swift': (files) => {
        const filesToLint = micromatch.not(files, ignoredFiles);
        return filesToLint.length
            ? [`swiftformat --lint ${filesToLint.join(' ')}`]
            : [];
    },
};
