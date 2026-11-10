[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../config/lab.config.json'),
    [string]$StatePath = (Join-Path $PSScriptRoot '../data/mock-state.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '../reports/access-audit.csv'),
    [ValidateSet('Mock', 'ActiveDirectory')][string]$Provider = 'Mock'
)
Import-Module (Join-Path $PSScriptRoot '../src/IAMLab.psm1') -Force
$results = @(Get-IamAccessAudit -ConfigPath $ConfigPath -StatePath $StatePath -Provider $Provider)
if ($results.Count -eq 0) { Write-Warning 'No user accounts found; no CSV was written.'; return }
$folder = Split-Path -Parent $OutputPath
if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Exported $($results.Count) audit rows to $OutputPath"
$results | Group-Object -Property Finding | Sort-Object Count -Descending | Select-Object Name, Count
