$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$env:DOCKER_BUILDKIT = '0'
$env:IMAGE_NAME = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'
$env:TESTS_DEBUG = 'verbose'

Set-Location C:\repo

Import-Module Pester -MinimumVersion 5.0.0
Write-Host ('= Pester version: {0}' -f (Get-Module Pester).Version)

$configuration = [PesterConfiguration]::Default
$configuration.Run.PassThru = $true
$configuration.Run.Path = '.\tests\sshAgent.Tests.ps1'
$configuration.Run.Exit = $false
$configuration.Output.Verbosity = 'Detailed'
$configuration.CodeCoverage.Enabled = $false
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = 'JUnitXml'
$configuration.TestResult.OutputPath = 'C:\repo\junit-results.xml'
# Exclude the two docker-build suites (classic-builder rebuild, far too slow here)
$configuration.Filter.FullName = @(
    '*image has setup-sshd.ps1 in the correct location*',
    '*image has no pre-existing SSH host keys*',
    '*checking image metadata*',
    '*image has expected tools versions installed and in the PATH*',
    '*create agent container with pubkey as argument*',
    '*create agent container with pubkey as envvar*',
    '*create agent container like docker-plugin*'
)

$r = Invoke-Pester -Configuration $configuration

Write-Host '=== RESULT SUMMARY ==='
Write-Host ("TOTAL={0} PASSED={1} FAILED={2} SKIPPED={3}" -f $r.TotalCount, $r.PassedCount, $r.FailedCount, $r.SkippedCount)
foreach ($t in $r.Tests) {
    Write-Host ("[{0}] {1}" -f $t.Result, $t.ExpandedPath)
}
Write-Host '=== FAILURE DETAILS ==='
foreach ($t in ($r.Tests | Where-Object { $_.Result -eq 'Failed' })) {
    Write-Host ("FAILED: {0}" -f $t.ExpandedPath)
    foreach ($e in $t.ErrorRecord) {
        Write-Host ("  MESSAGE: {0}" -f $e.Exception.Message)
        Write-Host ("  AT: {0}" -f $e.ScriptStackTrace)
    }
}
Write-Host ("PESTER_FAILED_COUNT={0}" -f $r.FailedCount)
