[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$StatePath = (Join-Path $PSScriptRoot '../data/mock-state.json'),
    [switch]$Force
)
Import-Module (Join-Path $PSScriptRoot '../src/IAMLab.psm1') -Force
Initialize-IamMockState -StatePath $StatePath -Force:$Force -WhatIf:$WhatIfPreference
