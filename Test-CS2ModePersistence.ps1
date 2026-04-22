#requires -version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Toggle', 'CS2', 'Normal')]
    [string]$Mode = 'Toggle',

    [ValidateRange(1, 120)]
    [int]$WaitSeconds = 10,

    [switch]$NoOverlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$toggleScript = Join-Path $scriptDir 'Toggle-CS2Mode.ps1'
$powerShellExe = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $powerShellExe)) {
    $powerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
}

if (-not (Test-Path -LiteralPath $toggleScript)) {
    throw "Toggle script not found: $toggleScript"
}

Write-Output ("[1/3] Running CS2 mode script with -Mode {0}..." -f $Mode)
$toggleArgs = @(
    '-NoProfile',
    '-STA',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $toggleScript,
    '-Mode',
    $Mode
)

if ($NoOverlay) {
    $toggleArgs += '-NoOverlay'
}

& $powerShellExe @toggleArgs
if ($LASTEXITCODE -ne 0) {
    throw "Toggle script exited with code $LASTEXITCODE."
}

Write-Output ("[2/3] Waiting {0} seconds to see whether Windows/NVIDIA reverts anything..." -f $WaitSeconds)
Start-Sleep -Seconds $WaitSeconds

Write-Output "[3/3] Reading current values from the system..."
& $powerShellExe -NoProfile -STA -ExecutionPolicy Bypass -File $toggleScript -Mode VerifyCurrent
if ($LASTEXITCODE -ne 0) {
    throw "Verification read exited with code $LASTEXITCODE."
}
