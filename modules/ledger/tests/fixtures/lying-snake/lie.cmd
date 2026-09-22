@echo off
rem The lying snake. FINDINGS.md F44 TEST 10.
rem
rem Invoke-LedgerForce resolves -PythonPath with Get-Command -CommandType Application and
rem then runs it with the CLI's argv. This stub ignores every argument and stdin, prints one
rem doctored result event, and exits 0 -- so the module reaches its identity check having
rem been handed a result that describes a run nobody requested.
type "%~dp0result-mismatch.ndjson"
