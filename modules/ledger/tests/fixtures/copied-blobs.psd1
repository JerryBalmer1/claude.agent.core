@{
    # Git blob shas of the files copied from claude.build.ledger@d57938d and still unmodified.
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
    # ledger.psd1 is deliberately absent. It is the ONE file the adapt commit changed, and it HAD
    # its own assertion, which reversed the change in memory and showed the source blob coming
    # back: that proved the diff was the RootModule filename and nothing else. F76 deleted that
    # assertion -- core makes no copy claim about its manifests -- so ManifestSourceSha at the
    # bottom of this file is now a record of what was measured, not an input to a live check.
    #
    # ledger.psm1 is absent for a different reason: its row was RETIRED, not broken. It was pinned
    # at 37d63403e7f0e21c5a8aa34ac6f80bbacb792d5a until core exported Add-LedgerRecord. Birth
    # fidelity to the source is recorded at core's birth commit and does not need re-asserting at
    # every HEAD; re-asserting it forbids core from ever changing its own ledger module. F76 set
    # the precedent. From that commit core's ledger module diverges from upstream ON PURPOSE, and
    # no row in this file claims otherwise.
    #
    # docs/commands.md is absent for the same reason as ledger.psm1, one axis over. It was pinned
    # at 4561a6acdc810c18ad61c18db90e012514417afd until core corrected it to the five-name export
    # list its own ledger.psd1 actually ships. A pin on a doc is a claim that the doc still
    # describes the SOURCE module, and once core's exports diverge on purpose that claim stops
    # being true and starts being a veto on fixing the doc. D002 again: retire the row, do not
    # re-pin. F88 measured the retirement and named the third file -- the hard-coded row count at
    # ledger.Tests.ps1:348 -- that has to move with it.
    #
    # docs/theory-of-operation.md stays pinned: PR #20 measured it as not stale on the export
    # axis, and it states no export list at all.
    #
    # tests/sandbox/ledger_chain.ps1 is absent since D010. It was pinned at
    # 2dbcbba94168d13a7193adf1e36381a2cea14309 until -Policy stopped resolving a sibling
    # claude.build.inspector and started refusing; its TEST 6 and TEST 9 asserted the removed
    # pass-through and were rewritten to assert the refusal. Same move as the rows above:
    # retire the row, do not re-pin, and drop the hard-coded count in ledger.Tests.ps1 with it.
    SourceRepo = 'claude.build.ledger'
    SourceSha  = 'd57938d1eed2b5df13435d7820826e50de30483d'

    Files = @(
        @{ Path = 'python/__init__.py';               Source = 'src/ledger/python/__init__.py';    Sha = '23304ab6c6b309e76fa432a29d551032c9fbc637' }
        @{ Path = 'python/cli.py';                    Source = 'src/ledger/python/cli.py';         Sha = '90dbd91f31b5964fb9e3b808da6239ff7b9553d6' }
        @{ Path = 'python/snake.py';                  Source = 'src/ledger/python/snake.py';       Sha = 'e9a4f06d77b00ca5807b31ed04ab6e5f7fc17ddb' }
        @{ Path = 'python/validators.py';             Source = 'src/ledger/python/validators.py';  Sha = '8f9bbbe4c2b475154fd43510ca0b610b6711aa4d' }
        @{ Path = 'python/requirements.txt';          Source = 'requirements.txt';                 Sha = 'd7f3e260185c6ff62fb019fee20b67e88f5d6a87' }
        @{ Path = 'docs/theory-of-operation.md';      Source = 'docs/theory-of-operation.md';      Sha = '3e4579539dbb805e55720d675dd85bdc32263272' }
        @{ Path = 'tests/sandbox/forensic_chain.ps1'; Source = 'tests/sandbox/forensic_chain.ps1'; Sha = '55b8c74403f6327d60a334969f8700cf06dfbe41' }
        @{ Path = 'tests/sandbox/fail_path.ps1';      Source = 'tests/sandbox/fail_path.ps1';      Sha = '02abe8bbeeab39e45d45970cdc75d8aa05d2e0b9' }
    )

    # The source manifest, before the adapt commit changed RootModule from 'Ledger.psm1' to
    # 'ledger.psm1'. Nothing on disk has this sha; the assertion reconstructs it.
    ManifestSourceSha = '0506e41c6426f00980deb4c2da84b5eaad639fc6'
}
