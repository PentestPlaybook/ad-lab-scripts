<#
  Automated Domain Join Script
  - Prompts user to confirm Tamper Protection is disabled (Y/N).
  - Prompts user to enter the computer name.
  - Sets DNS to domain controller.
  - Renames the computer (if needed).
  - Joins the domain and moves computer to the specified OU.
  - Syncs time with the domain controller.
  - Gives final login instructions.
  - Reboots at the end.
#>

[CmdletBinding()]
param(
    # ====== NETWORK SETTINGS ======
    [string]$DNSServer       = "10.10.14.2",

    # ====== DOMAIN INFO ======
    [string]$DomainName      = "AD.LAB",

    # ====== DOMAIN CREDENTIALS ======
    [string]$DomainAdminUser = "Administrator",

    # ====== LOCAL ADMIN CREDENTIALS (REQUIRED FOR RENAMING) ======
    [string]$LocalAdminUser  = "LocalUser",
    [string]$LocalAdminPass  = "password123!!",

    # ====== DOMAIN CONTROLLER HOSTNAME ======
    [string]$DCName          = "dc01.ad.lab"
)

### 0) Detect Network Adapter
$InterfaceName = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1).Name
if (-not $InterfaceName) {
    Write-Host "ERROR: No active network adapter found."
    exit 1
}
Write-Host "Using network adapter: $InterfaceName"

### 0b) Prompt for Computer Name
$ComputerName = Read-Host "Enter the desired computer name"

# Set Target OU based on Computer Name (case-insensitive check)
if ($ComputerName.ToUpper() -eq "ADMIN04") {
    $TargetOU = "OU=DisSMBSig\+DisPwdChg\+DisDef\+EnICMP,DC=AD,DC=LAB"
} else {
    $TargetOU = "OU=DisPwdChg\+DisDef\+EnICMP,DC=AD,DC=LAB"
}

### 1) Confirm Tamper Protection Disabled
Write-Host "Have you disabled Tamper Protection in Windows Security? (Y/N)"
$tpResponse = Read-Host
if ($tpResponse.ToUpper() -ne "Y") {
    Write-Host "Tamper Protection is not confirmed disabled. Exiting script."
    exit 1
}

### 2) Ensure Script is Running as Administrator
$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$AdminRole   = [Security.Principal.WindowsPrincipal]::new($CurrentUser)
if (-not $AdminRole.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator. Right-click PowerShell and choose 'Run as Administrator'."
    exit 1
}

### 3) Build Credential Objects
Write-Host "`n==> Creating Credential Objects..."
$FullDomainUser = "$DomainName\$DomainAdminUser"
$SecurePass     = Read-Host "Enter the Administrator password for $DomainName" -AsSecureString
$Cred           = New-Object System.Management.Automation.PSCredential($FullDomainUser, $SecurePass)

$LocalSecurePass = ConvertTo-SecureString $LocalAdminPass -AsPlainText -Force
$LocalCred       = New-Object System.Management.Automation.PSCredential($LocalAdminUser, $LocalSecurePass)

### 4) Set DNS Server
Write-Host "`n==> Setting DNS server to '$DNSServer' on '$InterfaceName'..."
try {
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceName -ServerAddresses $DNSServer -ErrorAction Stop
    Write-Host "DNS set successfully."
}
catch {
    Write-Host "ERROR setting DNS: $($_.Exception.Message)"
    exit 1
}

Write-Host "`n==> Waiting for network to stabilize..."
Start-Sleep -Seconds 5

### 5) Connectivity Checks
Write-Host "`n==> Checking connectivity to Domain Controller '$DCName'..."
if (-not (Test-Connection -ComputerName $DCName -Count 2 -Quiet)) {
    Write-Host "ERROR: Cannot reach domain controller '$DCName'. Check network settings."
    exit 1
}

Write-Host "`n==> Checking DNS resolution for Domain '$DomainName'..."
try {
    $ResolveDomain = Resolve-DnsName $DomainName -ErrorAction Stop
    Write-Host "DNS Resolution Successful: $($ResolveDomain.NameHost)"
}
catch {
    Write-Host "ERROR: Failed to resolve '$DomainName'. Check DNS settings."
    exit 1
}

### 6) Rename the Computer (Checkpoint: Skip if name already matches)
Write-Host "`n==> Checking if computer name is already '$ComputerName'..."
if ($env:COMPUTERNAME -eq $ComputerName) {
    Write-Host "Skipping rename - It's already '$ComputerName'."
}
else {
    Write-Host "Renaming computer to '$ComputerName' using local admin credentials..."
    try {
        Rename-Computer -NewName $ComputerName -LocalCredential $LocalCred -Force
        Write-Host "Computer renamed. (Will fully take effect after reboot.)"
    }
    catch {
        Write-Host "ERROR renaming computer: $($_.Exception.Message)"
        exit 1
    }
}

### 7) Join the Domain
Write-Host "`n==> Joining Domain '$DomainName' using '$FullDomainUser' with name '$ComputerName'..."
try {
    Add-Computer -DomainName $DomainName -Credential $Cred -NewName $ComputerName -Force -ErrorAction Stop -WarningAction SilentlyContinue
    Write-Host "Domain join succeeded (pending reboot)."
}
catch {
    Write-Host "ERROR joining domain: $($_.Exception.Message)"
    exit 1
}

### 8) Move Computer Object to Target OU
if (-not [string]::IsNullOrWhiteSpace($TargetOU)) {
    Write-Host "`n==> Attempting to move computer object '$ComputerName' to '$TargetOU'..."
    try {
        Invoke-Command -ComputerName $DCName -Credential $Cred -ScriptBlock {
            param($ComputerToMove, $OUPath)

            Import-Module ActiveDirectory -ErrorAction Stop

            $OU = Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop
            if (-not $OU) {
                Write-Host "ERROR: Specified OU '$OUPath' does not exist. Computer will remain in default location."
                exit 1
            }

            $comp = Get-ADComputer -Filter { Name -eq $ComputerToMove } -ErrorAction SilentlyContinue
            if (-not $comp) {
                Write-Host "ERROR: Computer object '$ComputerToMove' not found in AD. Check AD replication."
                exit 1
            }

            Move-ADObject -Identity $comp.DistinguishedName -TargetPath $OUPath -ErrorAction Stop
            Write-Host "Successfully moved '$ComputerToMove' to OU: $OUPath"
        } -ArgumentList $ComputerName, $TargetOU -ErrorAction Stop
    }
    catch {
        Write-Host "ERROR moving AD object: $($_.Exception.Message)"
        # do not exit; domain join itself succeeded
    }
}

### 9) Time Sync with Domain Controller
Write-Host "`n==> Syncing time with the domain..."
try {
    w32tm /resync
    Write-Host "Time sync command issued successfully."
}
catch {
    Write-Host "WARNING: Failed to sync time. $($_.Exception.Message)"
}

### 10) Final Instructions, Prompt & Reboot
Write-Host "`n=============================================================="
Write-Host "After joining this member workstation to the domain, on the login screen"
Write-Host "click 'Other User' and enter your domain credentials."
Write-Host "=============================================================="

Write-Host "`n==> Press ENTER to reboot and complete domain membership..."
Read-Host
Restart-Computer -Force
