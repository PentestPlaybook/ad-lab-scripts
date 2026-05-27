###############################################################################
# COMPLETE DOMAIN-CONTROLLER BUILD SCRIPT  (CHECKPOINT-RESUMABLE)
# ---------------------------------------------------------------------------
#  1. Static IP
#  2. Rename host → DC01
#  3. Install AD DS + DNS
#  4. Promote to new forest ad.lab
#  5. TLS cert for NTDS, import to Trusted Root
#  6. Seed test users (password-never-expires)
#  7. SPN for iis_service
#  8. User tweaks (Ernesto no-preauth, Jamie → Domain Admins)
#  9. Two custom GPOs
#       • Defender off, ICMP allow (both)
#       • SMB-signing off (2nd GPO only)
#     + Netlogon pwd settings (Default Domain Policy)
#     + Ctrl+Alt+Del **and** Power-button (ShutdownWithoutLogon) enabled on
#         – Default Domain Policy
#         – Default Domain Controllers Policy
# 10. Disable Windows Firewall (Domain / Private / Public)
###############################################################################

$CheckpointFile  = 'C:\DC-Setup-Checkpoint.txt'
$AdapterFile     = 'C:\DC-Setup-AdapterName.txt'

# ---------------------------------------------------------------------------
# DETECT / VALIDATE ADAPTER
# ---------------------------------------------------------------------------
if (-not (Test-Path $CheckpointFile)) {
    $adapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
    if ($adapters.Count -ne 1) {
        Write-Host "ERROR: Expected 1 active network adapter, found $($adapters.Count):"
        $adapters | Select-Object Name, InterfaceDescription, Status | Format-Table
        Write-Host "Please ensure only one network adapter is connected and re-run the script."
        return
    }
    $adapterName = $adapters[0].Name
    $adapterName | Out-File $AdapterFile -Force
    Write-Host "Found one active adapter: $adapterName"
    Read-Host "This script will reboot your device several times. Continue running the script after your computer reboots. When the setup is complete, the script will output 'Setup Complete'. Press ENTER to confirm."
}

$adapterName = if (Test-Path $AdapterFile) { Get-Content $AdapterFile } else { $null }

if (-not $adapterName) {
    Write-Host "ERROR: Adapter name file not found. Please delete $CheckpointFile and re-run the script."
    return
}

function Set-Checkpoint ($n){ $n | Out-File $CheckpointFile -Force }
function Get-Checkpoint { if(Test-Path $CheckpointFile){ Get-Content $CheckpointFile } else { 0 } }

$current = [int](Get-Checkpoint)
Write-Host "Checkpoint: $current"

# ---------------------------------------------------------------------------
# STEP 1 – STATIC IP
# ---------------------------------------------------------------------------
if ($current -lt 1) {
    Remove-NetIPAddress -InterfaceAlias $adapterName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    New-NetIPAddress  -InterfaceAlias $adapterName -IPAddress 10.10.14.1 -PrefixLength 24
    Set-DnsClientServerAddress $adapterName -ServerAddresses 10.10.14.1
    Set-Checkpoint 1
    Write-Host 'Step 1 complete - re-run script.'
    return
}

# ---------------------------------------------------------------------------
# STEP 2 – RENAME HOST → DC01
# ---------------------------------------------------------------------------
if ($current -lt 2) {
    if ($env:COMPUTERNAME -ne 'DC01') {
        Rename-Computer -NewName DC01 -Force
        Set-Checkpoint 2
        Restart-Computer -Force
    } else {
        Set-Checkpoint 2
    }
    return
}

# ---------------------------------------------------------------------------
# STEP 3 – INSTALL ROLES
# ---------------------------------------------------------------------------
if ($current -lt 3) {
    Install-WindowsFeature AD-Domain-Services,DNS -IncludeManagementTools
    Set-Checkpoint 3
    Write-Host 'Step 3 complete - re-run script.'
    return
}

# ---------------------------------------------------------------------------
# STEP 4 – PROMOTE TO DC
# ---------------------------------------------------------------------------
if ($current -lt 4) {
    $pwd = ConvertTo-SecureString 'P@ssw0rd123' -AsPlainText -Force
    Install-ADDSForest -DomainName ad.lab -DomainNetbiosName AD `
                       -SafeModeAdministratorPassword $pwd -InstallDNS -Force
    Set-Checkpoint 4
    return        # automatic reboot follows
}

# ---------------------------------------------------------------------------
# STEP 5 – CERT → NTDS + ROOT
# ---------------------------------------------------------------------------
if ($current -lt 5) {
    $cert = New-SelfSignedCertificate -DnsName dc01.ad.lab `
            -CertStoreLocation Cert:\LocalMachine\My `
            -KeyUsage DigitalSignature,KeyEncipherment -KeySpec KeyExchange `
            -TextExtension '2.5.29.37={text}1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2'
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters' `
                     -Name Certificate -Value $cert.Thumbprint
    $k = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
    icacls "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys\$k*" /grant 'NT AUTHORITY\SYSTEM:R' | Out-Null
    Export-Certificate -Cert $cert -FilePath C:\dc01.cer | Out-Null
    Import-Certificate -FilePath C:\dc01.cer -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Set-Checkpoint 5
    Write-Host 'Step 5 complete - re-run script.'
    return
}

# ---------------------------------------------------------------------------
# STEP 6 – USERS (NEVER EXPIRES)
# ---------------------------------------------------------------------------
if ($current -lt 6) {
    Import-Module ActiveDirectory
    function Add-User($N,$S,$U,$P){
        if(-not(Get-ADUser -Filter "SamAccountName -eq '$S'")){
            New-ADUser -Name $N -SamAccountName $S -UserPrincipalName $U `
                       -Path 'CN=Users,DC=ad,DC=lab' `
                       -AccountPassword (ConvertTo-SecureString $P -AsPlainText -Force) -Enabled $true
        }
        Set-ADUser $S -PasswordNeverExpires $true
    }
    Add-User Aaron Aaron aaron@ad.lab tt.r.2006
    Add-User Betty Betty betty@ad.lab pinky.1995
    Add-User Chris Chris chris@ad.lab abcABC123!@#
    Add-User Daniela Daniela daniela@ad.lab c/o2010
    Add-User Ernesto Ernesto ernesto@ad.lab lucky#1
    Add-User Francesca Francesca francesca@ad.lab bubbelinbunny_1
    Add-User Gregory Gregory gregory@ad.lab mc_monkey_1
    Add-User Helen Helen helen@ad.lab chase#1
    Add-User Issac Issac issac@ad.lab passw0rd!!
    Add-User Jamie Jamie jamie@ad.lab digital99.3
    Add-User iis_service iis_service iis_service@ad.lab daisy_3
    Set-Checkpoint 6
    Write-Host 'Step 6 complete - re-run script.'
    return
}

# ---------------------------------------------------------------------------
# STEP 7 – SPN
# ---------------------------------------------------------------------------
if ($current -lt 7) {
    setspn -S HTTP/web02.ad.lab AD\iis_service
    Set-Checkpoint 7
    Write-Host 'Step 7 complete - re-run script.'
    return
}

# ---------------------------------------------------------------------------
# STEP 8 – USER TWEAKS
# ---------------------------------------------------------------------------
if ($current -lt 8) {
    $uac = (Get-ADUser Ernesto -Properties userAccountControl).userAccountControl -bor 4194304
    Set-ADUser Ernesto -Replace @{userAccountControl=$uac}
    Add-ADGroupMember 'Domain Admins' Jamie
    Set-Checkpoint 8
    Write-Host 'Step 8 complete - re-run script.'
    return
}

# ------------------------------ HELPER --------------------------------------
function Disable-Defender($g){
    $base='HKLM\SOFTWARE\Policies\Microsoft\Windows Defender'
    Set-GPRegistryValue -Name $g -Key $base -ValueName DisableAntiSpyware -Type DWord -Value 1
    Set-GPRegistryValue -Name $g -Key "$base\Real-Time Protection" `
                        -ValueName DisableRealtimeMonitoring -Type DWord -Value 1
}

# ---------------------------------------------------------------------------
# STEP 9 – OUs / GPOs / DOMAIN POLICY EDITS
# ---------------------------------------------------------------------------
if ($current -lt 9) {
    Import-Module GroupPolicy

    $OU1='DisPwdChg_DisDef_EnICMP'
    $OU2='DisSMBSig_DisPwdChg_DisDef_EnICMP'
    $G1=$OU1; $G2=$OU2

    foreach($n in $OU1,$OU2){
        if(-not(Get-ADOrganizationalUnit -LDAPFilter "(ou=$n)")){
            New-ADOrganizationalUnit -Name $n -Path 'DC=ad,DC=lab'
        }
        if(-not(Get-GPO -Name $n -ErrorAction SilentlyContinue)){ New-GPO -Name $n | Out-Null }
    }

    $DN1=(Get-ADOrganizationalUnit -LDAPFilter "(ou=$OU1)").DistinguishedName
    $DN2=(Get-ADOrganizationalUnit -LDAPFilter "(ou=$OU2)").DistinguishedName
    New-GPLink -Name $G1 -Target $DN1 -LinkEnabled Yes
    New-GPLink -Name $G2 -Target $DN2 -LinkEnabled Yes

    # SMB signing off (G2 only)
    $srv='HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
    Set-GPRegistryValue -Name $G2 -Key $srv -ValueName RequireSecuritySignature -Type DWord -Value 0
    Set-GPRegistryValue -Name $G2 -Key $srv -ValueName EnableSecuritySignature  -Type DWord -Value 0

    # Defender off & ICMP allow (both)
    Disable-Defender $G1; Disable-Defender $G2
    foreach($ps in @("ad.lab\$G1","ad.lab\$G2")){
        New-NetFirewallRule -PolicyStore $ps -Name AllowICMP -DisplayName AllowICMP `
                            -Protocol ICMPv4 -IcmpType 8 -Profile Domain,Private -Action Allow `
                            -ErrorAction SilentlyContinue | Out-Null
    }

    # Default Domain Policy – Netlogon pwd settings
    $DDP='Default Domain Policy'
    $NLK='HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    Set-GPRegistryValue -Name $DDP -Key $NLK -ValueName DisablePasswordChange -Type DWord -Value 1
    Set-GPRegistryValue -Name $DDP -Key $NLK -ValueName MaximumPasswordAge   -Type DWord -Value 0

    # Ctrl+Alt+Del and power button
    $Sec='HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    foreach($pol in $DDP,'Default Domain Controllers Policy'){
        Set-GPRegistryValue -Name $pol -Key $Sec -ValueName DisableCAD           -Type DWord -Value 1
        Set-GPRegistryValue -Name $pol -Key $Sec -ValueName ShutdownWithoutLogon -Type DWord -Value 1
    }

    # Rename OUs and GPOs
    $OU1F='DisPwdChg+DisDef+EnICMP'
    $OU2F='DisSMBSig+DisPwdChg+DisDef+EnICMP'
    $G1F="${OU1F}_Policy"
    $G2F="${OU2F}_Policy"
    Rename-ADObject $DN1 -NewName $OU1F
    Rename-ADObject $DN2 -NewName $OU2F
    Rename-GPO      $G1  -TargetName $G1F
    Rename-GPO      $G2  -TargetName $G2F

    # Local machine power button (immediate effect on DC)
    New-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
                     -Name ShutdownWithoutLogon -PropertyType DWord -Value 1 -Force | Out-Null

    Set-Checkpoint 9
    Write-Host 'Step 9 complete - re-run script.'
    return
}

# ---------------------------------------------------------------------------
# STEP 10 – DISABLE WINDOWS FIREWALL
# ---------------------------------------------------------------------------
if ($current -lt 10) {
    Write-Host "`n[Step 10] Disabling Windows Firewall..."
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False
    Set-Checkpoint 10
    Write-Host "`n*****  SETUP FULLY COMPLETE  *****"
    return
}
