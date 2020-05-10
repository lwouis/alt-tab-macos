module.exports = {
    plugins: [
        ['@semantic-release/commit-analyzer', {
            'preset': 'angular',
            // having version increments and builds for these commit types is valuable
            'releaseRules': [
                {'type': 'perf', 'release': 'patch'},
                {'type': 'docs', 'release': 'patch'},
                {'type': 'style', 'release': 'patch'},
                {'type': 'refactor', 'release': 'patch'},
                {'type': 'test', 'release': 'patch'},
                {'type': 'chore', 'release': 'patch'},
                {'type': 'ci', 'release': 'patch'},
            ],
        }],
        '@semantic-release/release-notes-generator',
        ['@semantic-release/changelog', {
            'changelogTitle': '# Release notes',
            'changelogFile': 'docs/Changelog.md',
        }],
        ['@semantic-release/git', {
            'assets': [
                'docs/Changelog.md',
                'appcast.xml'
            ],
        }],
    ],
}
