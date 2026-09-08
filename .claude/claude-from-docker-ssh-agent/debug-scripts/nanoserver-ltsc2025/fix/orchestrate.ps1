$ErrorActionPreference = 'Stop'
$ProgressPreference  = 'SilentlyContinue'

$workDir = 'C:\repo'
$failed  = $false

Set-Location $workDir

$imageType   = 'nanoserver-ltsc2025'
$javaRelease = '21'

Write-Host ''
Write-Host ('=' * 60)
Write-Host "BUILD  image_type=$imageType  java_release=$javaRelease"
Write-Host ('=' * 60)

$env:IMAGE_TYPE            = $imageType
$env:JAVA_RELEASE_OVERRIDE = $javaRelease

& "$workDir\build.ps1" build
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: build failed for $imageType jdk$javaRelease"
    exit 1
}

Write-Host ''
Write-Host ('=' * 60)
Write-Host "TEST   image_type=$imageType  java_release=$javaRelease"
Write-Host ('=' * 60)

& "$workDir\build.ps1" test
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: tests failed for $imageType jdk$javaRelease"
    exit 1
}

Write-Host ''
Write-Host 'Build and tests completed successfully.'
exit 0
