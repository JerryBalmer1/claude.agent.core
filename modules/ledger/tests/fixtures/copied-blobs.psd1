@{
    # Git blob shas of every file copied from claude.build.ledger@d57938d, unmodified.
    #
    # The scaffold commit (subject: "scaffold: copy claude.build.ledger@d57938d src+docs+suites,
    # unmodified") measured each of these THREE ways and recorded them in its body: the source
    # repository at the copy sha, the source working tree, and this tree. ledger.Tests.ps1
    # recomputes them a FOURTH way, from the bytes on disk, with no git involved -- so the claim
    # "byte-identical" survives an export with no .git directory, and an index that disagrees with
    # the file cannot launder an edit.
    #
    # Reproduce any row without trusting this file:
    #   git -C <substrate>           hash-object -- modules/ledger/<path>
    #   git -C <claude.build.ledger> rev-parse d57938d:<source path>
    #
    # ledger.psd1 is deliberately absent. It is the ONE file the adapt commit changed, and it has
    # its own assertion, which reverses the change in memory and shows the source blob coming back:
    # that proves the diff is the RootModule filename and nothing else.
    SourceRepo = 'claude.build.ledger'
    SourceSha  = 'd57938d1eed2b5df13435d7820826e50de30483d'

    Files = @(
        @{ Path = 'ledger.psm1';                      Source = 'src/ledger/Ledger.psm1';           Sha = '37d63403e7f0e21c5a8aa34ac6f80bbacb792d5a' }
        @{ Path = 'python/__init__.py';               Source = 'src/ledger/python/__init__.py';    Sha = '23304ab6c6b309e76fa432a29d551032c9fbc637' }
        @{ Path = 'python/cli.py';                    Source = 'src/ledger/python/cli.py';         Sha = '90dbd91f31b5964fb9e3b808da6239ff7b9553d6' }
        @{ Path = 'python/snake.py';                  Source = 'src/ledger/python/snake.py';       Sha = 'e9a4f06d77b00ca5807b31ed04ab6e5f7fc17ddb' }
        @{ Path = 'python/validators.py';             Source = 'src/ledger/python/validators.py';  Sha = '8f9bbbe4c2b475154fd43510ca0b610b6711aa4d' }
        @{ Path = 'python/requirements.txt';          Source = 'requirements.txt';                 Sha = 'd7f3e260185c6ff62fb019fee20b67e88f5d6a87' }
        @{ Path = 'docs/theory-of-operation.md';      Source = 'docs/theory-of-operation.md';      Sha = '3e4579539dbb805e55720d675dd85bdc32263272' }
        @{ Path = 'docs/commands.md';                 Source = 'docs/commands.md';                 Sha = '4561a6acdc810c18ad61c18db90e012514417afd' }
        @{ Path = 'tests/sandbox/ledger_chain.ps1';   Source = 'tests/sandbox/ledger_chain.ps1';   Sha = '2dbcbba94168d13a7193adf1e36381a2cea14309' }
        @{ Path = 'tests/sandbox/forensic_chain.ps1'; Source = 'tests/sandbox/forensic_chain.ps1'; Sha = '55b8c74403f6327d60a334969f8700cf06dfbe41' }
        @{ Path = 'tests/sandbox/fail_path.ps1';      Source = 'tests/sandbox/fail_path.ps1';      Sha = '02abe8bbeeab39e45d45970cdc75d8aa05d2e0b9' }
    )

    # The source manifest, before the adapt commit changed RootModule from 'Ledger.psm1' to
    # 'ledger.psm1'. Nothing on disk has this sha; the assertion reconstructs it.
    ManifestSourceSha = '0506e41c6426f00980deb4c2da84b5eaad639fc6'
}
