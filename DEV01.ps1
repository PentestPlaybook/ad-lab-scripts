# ============================================================
# Deploy_With_Pauses_Domain_PluginCreation.ps1
#
# This script performs automated actions and pauses when
# manual intervention is required. When the script reaches a
# manual step, you'll be prompted to complete the action and
# type "Y" to continue.
#
# NOTE: Run this script as Administrator.
# ============================================================

# Function to pause for manual step confirmation.
function Confirm-ManualStep($stepDescription) {
    Write-Host ""
    Write-Host "MANUAL STEP REQUIRED: $stepDescription" -ForegroundColor Yellow
    do {
        $response = Read-Host "After completing the above step, type 'Y' to continue"
    } while ($response -notin @("Y", "y"))
    Write-Host "Continuing..."
    Write-Host ""
}

# --- Ensure the script is running with elevated privileges ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator. Exiting."
    exit
}

# ------------------- Step 4 -------------------
Write-Host "Step 4: Creating application root directory at C:\MyService..."
New-Item -Path "C:\MyService" -ItemType Directory -Force

Write-Host "Adding Windows Defender exclusion for C:\MyService..."
Add-MpPreference -ExclusionPath "C:\MyService"

# ------------------- Step 5 -------------------
Write-Host "Step 5: Creating dummy program.exe in C:\MyService..."
$dummyContent = "This is a dummy executable for demonstration purposes."
Set-Content -Path "C:\MyService\program.exe" -Value $dummyContent

# ------------------- Step 6 -------------------
Write-Host "Step 6: Creating service 'MyService'..."
New-Service -Name "MyService" -BinaryPathName "C:\MyService\program.exe" -DisplayName "MyService" -StartupType Automatic

Write-Host "Verifying service configuration..."
sc.exe qc MyService
Get-Service MyService

# ------------------- Step 7 -------------------
Write-Host "Step 7: Modifying permissions on C:\MyService and its files..."
icacls "C:\MyService" /inheritance:r
icacls "C:\MyService" /grant "BUILTIN\Users:(OI)(CI)M" /T
icacls "C:\MyService" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)(F)" /T

Write-Host "Verifying permissions for program.exe and C:\MyService..."
icacls "C:\MyService\program.exe"
icacls "C:\MyService"

# ------------------- Step 8 -------------------
Confirm-ManualStep "Install XAMPP for Windows:
  a. Download from https://www.apachefriends.org/
  b. Run the installer from your Downloads folder, click 'Allow' on the UAC Prompt to allow Apache, and choose the default options to install Apache"

# ------------------- Steps 9 & 12 -------------------
if (Test-Path "C:\xampp\apache\bin\httpd.exe") {
    Write-Host "Step 9/12: Checking Apache configuration..."
    $httpdTestOutput = & "C:\xampp\apache\bin\httpd.exe" -t 2>&1
    if ($httpdTestOutput -match "Syntax OK") {
        Write-Host "Apache configuration is valid."
        Write-Host "Installing Apache as a service..."
        $installOutput = & "C:\xampp\apache\bin\httpd.exe" -k install 2>&1
        if ($installOutput -match "Errors reported here must be corrected") {
            Write-Host "Note: The installer reported configuration errors, but the configuration test passed. Proceeding with installation."
        }
    }
    else {
        Write-Error "Apache configuration error: $httpdTestOutput"
        exit
    }
} else {
    Write-Warning "Apache httpd.exe not found. Ensure XAMPP is installed in C:\xampp."
}

# ------------------- Step 13 -------------------
Write-Host "Step 13: Starting Apache and MySQL services..."
Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
Start-Service -Name "mysql" -ErrorAction SilentlyContinue

# ------------------- Steps 14-16: MySQL Database/User Setup -------------------
Confirm-ManualStep "Configure MySQL via phpMyAdmin:
1. Start MySQL in XAMPP Control Panel and click 'Allow' on the UAC Prompt for mysqld.
2. Open your web browser and navigate to http://localhost/phpmyadmin.
3. Click the 'Databases' tab.
   - In the 'Database name' field, type 'wp_lab' and click 'Create'.
4. Return to the phpMyAdmin home page by clicking the 'phpMyAdmin' icon.
5. Click the 'User accounts' tab, then click 'Add User Account' under 'New'.
6. Under 'Add User Account', enter the following:
   - User Name: mysql
   - Host name: localhost
   - Password: Password123 (enter it twice)
   - Click 'Go'.
7. Click 'User accounts' and then click 'mysql'
8. Click 'Database', select 'wp_lab' from the dropdown and click 'Go'.
9. Select the checkbox next to 'Check all', for 'Database Specific Privileges' and click 'Go'."

# ------------------- Step 17 -------------------
$wordpressZip = "$env:TEMP\wordpress.zip"
Write-Host "Step 17: Downloading WordPress 6.7.2..."
Invoke-WebRequest -Uri "https://wordpress.org/wordpress-6.7.2.zip" -OutFile $wordpressZip

$wordpressDest = "C:\xampp\htdocs\wordpress"
Write-Host "Extracting WordPress to $wordpressDest..."
Expand-Archive -Path $wordpressZip -DestinationPath $wordpressDest -Force
Remove-Item $wordpressZip

# ------------------- Step 18 -------------------
Confirm-ManualStep "Run the WordPress installer:
  a. Open your browser and navigate to http://localhost/wordpress/
  b. Click 'wordpress/'
  c. Select your language and click 'Continue'
  d. Click 'Let's go!'
  e. In the Database Connection screen, enter:
       - Database Name: wp_lab
       - Username: mysql
       - Password: Password123
       - Database Host: localhost
       - Table Prefix: wp_
  f. Click 'Submit' then 'Run the installation'
  g. On the Welcome page, enter the following:
       - Site Title: admin-site
       - Username: ernesto
       - Password: lucky#1 (and check 'Confirm use of weak password')
       - Your Email: ernesto@ad.lab
  h. Click 'Install WordPress'.
  i. Click 'Log In', then enter ernesto's credentials and log in."

# ------------------- Step 19: Create Plugin File and ZIP It -------------------
Write-Host "Step 19: Creating the plugin file and compressing it into plugin.php.zip..."
$pluginFile = Join-Path -Path (Get-Location) -ChildPath "plugin.php"
$pluginZip = Join-Path -Path (Get-Location) -ChildPath "plugin.php.zip"
$pluginContent = @'
<?php
/*
Plugin Name: Backup and Migration
Description: Backup plugin that allows you to specify an SMB share for storing backups.
Version: 1.0
Author: Your Name
*/

if ( ! defined( 'ABSPATH' ) ) {
    exit; // Exit if accessed directly.
}

// Add the admin menu page.
add_action('admin_menu', 'bam_add_admin_menu');
function bam_add_admin_menu() {
    add_menu_page(
        'Backup and Migration',
        'Backup and Migration',
        'manage_options',
        'backup-and-migration',
        'bam_settings_page',
        'dashicons-backup',
        90
    );
}

// Initialize and register settings.
add_action('admin_init', 'bam_settings_init');
function bam_settings_init() {
    register_setting('bam_settings', 'bam_options');

    add_settings_section(
        'bam_section',
        __('SMB Backup Settings', 'backup-and-migration'),
        'bam_section_callback',
        'bam_settings'
    );

    add_settings_field(
        'bam_smb_share',
        __('Backup Storage Location (SMB share)', 'backup-and-migration'),
        'bam_smb_share_render',
        'bam_settings',
        'bam_section'
    );

    add_settings_field(
        'bam_smb_username',
        __('SMB Username', 'backup-and-migration'),
        'bam_smb_username_render',
        'bam_settings',
        'bam_section'
    );

    add_settings_field(
        'bam_smb_password',
        __('SMB Password', 'backup-and-migration'),
        'bam_smb_password_render',
        'bam_settings',
        'bam_section'
    );
}

function bam_smb_share_render() {
    $options = get_option('bam_options');
    ?>
    <input type="text" name="bam_options[bam_smb_share]" value="<?php echo isset($options['bam_smb_share']) ? esc_attr($options['bam_smb_share']) : ''; ?>" size="50" />
    <p class="description">Enter the network share path, e.g. <code>\\10.10.14.120\samba</code></p>
    <?php
}

function bam_smb_username_render() {
    $options = get_option('bam_options');
    ?>
    <input type="text" name="bam_options[bam_smb_username]" value="<?php echo isset($options['bam_smb_username']) ? esc_attr($options['bam_smb_username']) : ''; ?>" />
    <?php
}

function bam_smb_password_render() {
    $options = get_option('bam_options');
    ?>
    <input type="password" name="bam_options[bam_smb_password]" value="<?php echo isset($options['bam_smb_password']) ? esc_attr($options['bam_smb_password']) : ''; ?>" />
    <?php
}

function bam_section_callback() {
    echo __('Configure the SMB share for storing backups.', 'backup-and-migration');
}

// Render the settings page.
function bam_settings_page() {
    ?>
    <div class="wrap">
        <h1>Backup and Migration Settings</h1>
        <form action="options.php" method="post">
            <?php
                settings_fields('bam_settings');
                do_settings_sections('bam_settings');
                submit_button();
            ?>
        </form>

        <h2>Test SMB Connection</h2>
        <form method="post">
            <?php submit_button('Test Connection', 'secondary', 'bam_test_connection'); ?>
        </form>
        <?php
        if ( isset($_POST['bam_test_connection']) ) {
            echo '<h3>Connection Test Result:</h3>';
            echo '<pre>';
            echo bam_test_smb_connection();
            echo '</pre>';
        }
        ?>
    </div>
    <?php
}

/**
 * Test the SMB connection using the php-smbclient extension.
 */
function bam_test_smb_connection() {
    $options = get_option('bam_options');

    if ( empty($options['bam_smb_share']) ) {
        return "SMB share path not set.";
    }

    // Convert Windows-style share (e.g. \\10.10.14.120\samba) to smb:// format.
    $share = $options['bam_smb_share'];
    $smb_url = preg_replace('#^\\\\\\\\([^\\\\]+)\\\\([^\\\\]+)#', 'smb://$1/$2', $share);

    if ( ! function_exists('smbclient_state_new') ) {
        return "PHP smbclient extension is not installed or enabled.";
    }

    $smb = smbclient_state_new();
    if ( ! $smb ) {
        return "Failed to initialize SMB client state.";
    }

    $username = isset($options['bam_smb_username']) ? $options['bam_smb_username'] : '';
    $password = isset($options['bam_smb_password']) ? $options['bam_smb_password'] : '';
    if ( $username !== '' ) {
        $smb_url = preg_replace('#^(smb://)#', '${1}' . rawurlencode($username) . ':' . rawurlencode($password) . '@', $smb_url);
    }

    $dir = @smbclient_opendir($smb, $smb_url);
    if ( ! $dir ) {
        return "Unable to open SMB share at $smb_url. Check credentials and share path.";
    }

    $files = [];
    while (($file = smbclient_readdir($smb, $dir)) !== false) {
        $files[] = $file;
    }
    smbclient_closedir($smb, $dir);

    return "Connection successful. Directory contents:\n" . implode("\n", $files);
}
'@

# Write the plugin content to plugin.php
Set-Content -Path $pluginFile -Value $pluginContent -Encoding UTF8
Write-Host "Created plugin file: $pluginFile"

# Compress plugin.php into plugin.php.zip
if (Test-Path $pluginZip) { Remove-Item $pluginZip -Force }
Compress-Archive -Path $pluginFile -DestinationPath $pluginZip
Write-Host "Compressed plugin file into: $pluginZip"

# Optionally, remove the unzipped plugin.php file
Remove-Item $pluginFile -Force

# ------------------- Step 20: Plugin Installation -------------------
Confirm-ManualStep "Install and activate the plugin via the WordPress admin dashboard:
  a. In WordPress, go to Dashboard -> Plugins -> Add New Plugin -> Upload Plugin -> Choose File
  b. Select the file 'plugin.php.zip' from the current directory, click ""Open"", click ""Install Now"", click ""Activate Plugin"""

# ------------------- Step 21 -------------------
Write-Host "Step 21: Configuring Apache service to run under domain account 'AD.LAB\francesca'..."
$changeOutput = sc.exe config "Apache2.4" obj= "AD.LAB\francesca" password= "bubbelinbunny_1"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure Apache to run under 'AD.LAB\francesca'.
Ensure that:
  - The domain account 'AD.LAB\francesca' exists,
  - It has the 'Log on as a service' right,
  - And the password is correct.
Alternatively, if this is not a domain account, use a local account (e.g., '.\francesca')."
    exit
}

Write-Host "Deployment script completed."
