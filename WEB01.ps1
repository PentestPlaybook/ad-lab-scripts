# ============================================================
# Deploy_XAMPP_LoginSystem_Setup.ps1
#
# This script automates parts of the XAMPP login system setup
# and prompts for manual steps where necessary.
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

# ------------------- Step 4: Install XAMPP for Windows -------------------
Confirm-ManualStep "Install XAMPP for Windows:
a. Go to: https://www.apachefriends.org/
b. Click 'XAMPP for Windows'
c. Double-click the XAMPP installer (in the Downloads folder) and click 'Next' to choose the default options in the installer and confirm the UAC prompt for Apache."

# ------------------- Step 5: Start Apache and MySQL in XAMPP Control Panel -------------------
Confirm-ManualStep "Start Apache and MySQL in XAMPP Control Panel:
a. Click 'Start' next to 'Apache'
b. Click 'Start' next to 'MySQL' and confirm the UAC prompt for mysqld."

# ------------------- Step 5.1: Enable Apache and MySQL to Start at System Startup -------------------
Write-Host "Enabling Apache and MySQL to start automatically at system startup..."

# Enable Apache Service
$apacheServiceName = "Apache2.4"
if (Get-Service -Name $apacheServiceName -ErrorAction SilentlyContinue) {
    Set-Service -Name $apacheServiceName -StartupType Automatic
    Write-Host "Apache service ($apacheServiceName) set to Automatic."
} else {
    Write-Host "Apache service ($apacheServiceName) not found. Installing Apache service..."
    & "C:\xampp\apache\bin\httpd.exe" -k install
    if (Get-Service -Name $apacheServiceName -ErrorAction SilentlyContinue) {
        Set-Service -Name $apacheServiceName -StartupType Automatic
        Write-Host "Apache service installed and set to Automatic."
    } else {
        Write-Host "Failed to install Apache service. Please install it manually."
    }
}

# Enable MySQL Service
$mysqlServiceName = "mysql"
if (Get-Service -Name $mysqlServiceName -ErrorAction SilentlyContinue) {
    Set-Service -Name $mysqlServiceName -StartupType Automatic
    Write-Host "MySQL service ($mysqlServiceName) set to Automatic."
} else {
    Write-Host "MySQL service ($mysqlServiceName) not found. Installing MySQL service..."
    & "C:\xampp\mysql\bin\mysqld.exe" --install
    if (Get-Service -Name $mysqlServiceName -ErrorAction SilentlyContinue) {
        Set-Service -Name $mysqlServiceName -StartupType Automatic
        Write-Host "MySQL service installed and set to Automatic."
    } else {
        Write-Host "Failed to install MySQL service. Please install it manually."
    }
}

# ------------------- Step 6: Create MySQL Database 'login_system' -------------------
Confirm-ManualStep "Create a MySQL database named 'login_system':
a. Click 'Admin' next to 'MySQL' in XAMPP Control Panel.
b. Click 'Databases' in the phpMyAdmin window.
c. Type 'login_system' in the text entry box and click 'Create'."

# ------------------- Step 7: Create the Users Table -------------------
Write-Host "Step 7: Create the Users table by running the following SQL query in phpMyAdmin:"
Write-Host "  CREATE TABLE users (" -ForegroundColor Cyan
Write-Host "      id INT AUTO_INCREMENT PRIMARY KEY," -ForegroundColor Cyan
Write-Host "      username VARCHAR(50) NOT NULL UNIQUE," -ForegroundColor Cyan
Write-Host "      password VARCHAR(255) NOT NULL" -ForegroundColor Cyan
Write-Host "  );" -ForegroundColor Cyan

Confirm-ManualStep "Instructions:
  a. Click 'Query'
  b. Paste the above query into the code editor
  c. Click 'Submit Query' to execute the query."

# ------------------- Step 8: Add a User to the Table -------------------
Write-Host "Step 8: Add a user to the table by running the following SQL query in phpMyAdmin:"
Write-Host "  INSERT INTO users (username, password)" -ForegroundColor Cyan
Write-Host "  VALUES ('mysql', MD5('MySQLPassword123'));" -ForegroundColor Cyan

Confirm-ManualStep "Instructions:
  a. Paste the above query into the code editor
  b. Click 'Submit Query' to execute the query."

# ------------------- Step 9: Update the Root User's Password -------------------
Write-Host "Step 9: Update the Root user's password by running the following SQL query in phpMyAdmin:"
Write-Host "  ALTER USER 'root'@'localhost' IDENTIFIED BY 'tt.r.2006';" -ForegroundColor Cyan

Confirm-ManualStep "Instructions:
  a. Paste the above query into the code editor
  b. Click 'Submit Query' to execute the query."

# ------------------- Step 10: Update the MySQL Configuration File -------------------
Confirm-ManualStep "Update the MySQL configuration file with the new password:
a. Open the file C:\xampp\phpMyAdmin\config.inc.php using the command: notepad C:\xampp\phpMyAdmin\config.inc.php
b. Add 'tt.r.2006' as the password in the configuration file (e.g., \$cfg['Servers'][\$i]['password'] = 'tt.r.2006';).
c. Save and close the file.
d. Click 'Query' to reload the page and confirm the SQL connection."

# ------------------- Step 11: Create index.php -------------------
$indexPhpContent = @'
<?php
// Database configuration
$dbHost = 'localhost';
$dbUser = 'root';
$dbPass = 'tt.r.2006';
$dbName = 'login_system';

// Create connection
$conn = new mysqli($dbHost, $dbUser, $dbPass, $dbName);

// Check connection
if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

// Intentionally vulnerable code
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Directly using user input in the query, no sanitization
    $username = $_POST['username'];
    $password = $_POST['password'];

    // This query remains vulnerable to SQL injection: "' OR '1'='1" etc.
    $sql = "SELECT * FROM users WHERE username='$username' AND password=MD5('$password')";

    // For debugging only, do not enable on a real server:
    // echo "<pre>Query: $sql</pre>";

    $result = $conn->query($sql);

    if ($result && $result->num_rows > 0) {
        echo "Login successful! Welcome, " . htmlspecialchars($username) . ".";
    } else {
        echo "Invalid username or password.";
    }
}

$conn->close();
?>
'@

Write-Host "Step 11: Creating index.php in C:\xampp\htdocs\index.php..."
Set-Content -Path "C:\xampp\htdocs\index.php" -Value $indexPhpContent -Encoding UTF8

# ------------------- Step 12: Create index.html -------------------
$indexHtmlContent = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vulnerable Login</title>
</head>
<body>
    <h2>Vulnerable Login</h2>
    <form action="index.php" method="POST">
        <label for="username">Username:</label>
        <input type="text" id="username" name="username" required><br><br>

        <label for="password">Password:</label>
        <input type="password" id="password" name="password" required><br><br>

        <button type="submit">Login</button>
    </form>
</body>
</html>
'@

Write-Host "Step 12: Creating index.html in C:\xampp\htdocs\index.html..."
Set-Content -Path "C:\xampp\htdocs\index.html" -Value $indexHtmlContent -Encoding UTF8

# ------------------- Step 13: Add Windows Defender Exclusion -------------------
Write-Host "Step 13: Adding Windows Defender exclusion for C:\xampp\htdocs..."
Add-MpPreference -ExclusionPath "C:\xampp\htdocs"

Write-Host "XAMPP Login System setup script completed."
