[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CsvPath = (Join-Path $PSScriptRoot '../data/activate.csv'),
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../config/lab.config.json'),
    [string]$StatePath = (Join-Path $PSScriptRoot '../data/mock-state.json'),
    [ValidateSet('Mock', 'ActiveDirectory')][string]$Provider = 'Mock',
    [switch]$Execute,
    [Security.SecureString]$InitialPassword
)
Import-Module (Join-Path $PSScriptRoot '../src/IAMLab.psm1') -Force
Invoke-IamActivate -CsvPath $CsvPath -ConfigPath $ConfigPath -StatePath $StatePath -Provider $Provider -Execute:$Execute -InitialPassword $InitialPassword -WhatIf:$WhatIfPreference
