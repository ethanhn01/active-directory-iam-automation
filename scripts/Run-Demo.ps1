# One-command walkthrough of the OFFLINE fictional mock lab.
[CmdletBinding()]
param(
    [string]$StatePath = (Join-Path $PSScriptRoot '../data/mock-state.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '../reports/access-audit.csv'),
    [switch]$Reset
)
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '../src/IAMLab.psm1'
Import-Module $modulePath -Force
$config = Join-Path $PSScriptRoot '../config/lab.config.json'
$hires = Join-Path $PSScriptRoot '../data/new-hires.csv'
$activations = Join-Path $PSScriptRoot '../data/activate.csv'
$exits = Join-Path $PSScriptRoot '../data/offboarding.csv'
if ((Test-Path -LiteralPath $StatePath) -and -not $Reset) {
    throw "Demo state already exists: $StatePath. To intentionally start over, add -Reset."
}
Write-Host '1. Initialize fictional mock state'
Initialize-IamMockState -StatePath $StatePath -Force:$Reset | Out-Host
Write-Host '2. Provision 20 disabled identities'
Invoke-IamOnboard -CsvPath $hires -ConfigPath $config -StatePath $StatePath -Execute -Confirm:$false |
    Group-Object Status | Select-Object Name,Count | Format-Table | Out-Host
Write-Host '3. Simulate credential approval and activate 20 identities'
Invoke-IamActivate -CsvPath $activations -ConfigPath $config -StatePath $StatePath -Execute -Confirm:$false |
    Group-Object Status | Select-Object Name,Count | Format-Table | Out-Host
Write-Host '4. Offboard two identities'
Invoke-IamOffboard -CsvPath $exits -ConfigPath $config -StatePath $StatePath -Execute -Confirm:$false |
    Group-Object Status | Select-Object Name,Count | Format-Table | Out-Host
Write-Host '5. Export RBAC access review'
& (Join-Path $PSScriptRoot 'Export-AccessAudit.ps1') -ConfigPath $config -StatePath $StatePath -OutputPath $OutputPath | Out-Host
Write-Host 'Demo completed. Examine reports/access-audit.csv and data/mock-state.json.'
