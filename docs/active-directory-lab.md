# Optional Active Directory (AD DS) lab setup

**This is only for a disposable Windows Server domain you own or are explicitly authorized to test.** The default mock provider is sufficient to demonstrate the automation and pass the offline tests.

## Prerequisites

- VirtualBox, Hyper-V, or another virtualization platform capable of running a Windows Server VM.
- A Windows Server evaluation instance promoted to a domain controller for the **fictional domain** `democorp.test`, isolated from corporate networks.
- Active Directory PowerShell module installed and available on the server or authorized Windows admin VM. For example, Windows Server's AD DS role includes relevant administration tools.
- Sufficient privilege **in this lab** to create disabled accounts in a dedicated OU and manage only your lab groups.

Microsoft references: [Install AD DS](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/install-active-directory-domain-services--level-100-) and [AD PowerShell cmdlets](https://learn.microsoft.com/en-us/powershell/module/activedirectory/).

## Step 1: Set up a dedicated OU and lab groups

On the **disposable domain controller only**, after configuring the domain and AD module:

```powershell
Import-Module ActiveDirectory

New-ADOrganizationalUnit -Name 'LabUsers' -Path 'DC=democorp,DC=test' -ProtectedFromAccidentalDeletion $true

'GG-IT-Standard','GG-HR-Standard','GG-Finance-Standard','GG-Operations-Standard' |
    ForEach-Object {
        New-ADGroup -Name $_ -SamAccountName $_ -GroupScope Global -GroupCategory Security `
            -Path 'OU=LabUsers,DC=democorp,DC=test'
    }
