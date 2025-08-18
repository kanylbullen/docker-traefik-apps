# PowerShell setup script for Windows - Enhanced Version
# =============================================================================
# Homelab Quick Setup Script (Windows) - Enhanced
# =============================================================================

param(
    [switch]$Force,
    [string]$Profile = "base"
)

# Enhanced error handling
$ErrorActionPreference = "Stop"

# Colors for output
$colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Blue"
    Cyan = "Cyan"
}

function Write-Header {
    param($Message)
    Write-Host "=== $Message ===" -ForegroundColor $colors.Blue
}

function Write-Success {
    param($Message)
    Write-Host "✓ $Message" -ForegroundColor $colors.Green
}

function Write-Warning {
    param($Message)
    Write-Host "⚠ $Message" -ForegroundColor $colors.Yellow
}

function Write-Error {
    param($Message)
    Write-Host "✗ $Message" -ForegroundColor $colors.Red
}

function Write-Info {
    param($Message)
    Write-Host "ℹ $Message" -ForegroundColor $colors.Cyan
}

# Cleanup function for error recovery
function Invoke-Cleanup {
    Write-Error "Setup failed, performing cleanup..."
    try {
        docker compose down --remove-orphans 2>$null
        Write-Info "Cleanup completed. You can safely retry the setup."
    } catch {
        Write-Warning "Cleanup encountered issues, but continuing..."
    }
}

# System requirements check
function Test-SystemRequirements {
    Write-Header "System Requirements Check"
    
    # Check available disk space (minimum 2GB)
    $drive = Get-PSDrive -Name ([System.IO.Path]::GetPathRoot((Get-Location).Path).TrimEnd('\'))
    $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
    
    if ($freeSpaceGB -lt 2) {
        Write-Error "Insufficient disk space. At least 2GB required, found: $freeSpaceGB GB"
        exit 1
    }
    Write-Success "Sufficient disk space available: $freeSpaceGB GB"
    
    # Check if ports are available
    $portsInUse = @()
    try {
        if (Get-NetTCPConnection -LocalPort 80 -ErrorAction SilentlyContinue) { $portsInUse += "80" }
        if (Get-NetTCPConnection -LocalPort 443 -ErrorAction SilentlyContinue) { $portsInUse += "443" }
    } catch {
        # Ignore errors if unable to check ports
    }
    
    if ($portsInUse.Count -gt 0) {
        Write-Warning "Ports $($portsInUse -join ', ') appear to be in use. This may cause conflicts."
        $continue = Read-Host "Continue anyway? (y/N)"
        if ($continue -notmatch "^[Yy]$") {
            exit 1
        }
    }
    Write-Success "Required ports appear to be available"
    
    # Check Docker version
    try {
        $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
        Write-Success "Docker version: $dockerVersion"
    } catch {
        Write-Success "Docker version: unknown"
    }
    
    # Check Docker Compose version
    try {
        $composeVersion = docker compose version --short 2>$null
        Write-Success "Docker Compose version: $composeVersion"
    } catch {
        Write-Success "Docker Compose version: unknown"
    }
}

Write-Header "Homelab Setup Script (Windows) - Enhanced"

# Run system requirements check
Test-SystemRequirements

# Check if .env exists
if (-not (Test-Path ".env")) {
    Write-Warning ".env file not found. Copying from .env.example..."
    Copy-Item ".env.example" ".env"
    Write-Success "Created .env file"
    Write-Warning "Please edit .env file with your configuration before continuing!"
    Read-Host "Press enter when you've configured .env"
}

# Load environment variables from .env
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^([^#][^=]+)=(.*)$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

# Validate required environment variables
Write-Header "Validating Configuration"

$requiredVars = @("DOMAIN", "ACME_EMAIL", "CF_DNS_API_TOKEN", "TS_AUTHKEY")
$missingVars = @()

foreach ($var in $requiredVars) {
    $value = [Environment]::GetEnvironmentVariable($var)
    if ([string]::IsNullOrEmpty($value) -or 
        $value -eq "example.com" -or 
        $value.Contains("change-me") -or 
        $value.Contains("put-your")) {
        $missingVars += $var
    }
}

if ($missingVars.Count -gt 0) {
    Write-Error "Missing or placeholder values for: $($missingVars -join ', ')"
    Write-Error "Please edit .env file with real values"
    exit 1
}

Write-Success "Configuration validated"

# Create necessary directories
Write-Header "Creating Directories"

$traefikAcmePath = "traefik/acme"
if (-not (Test-Path $traefikAcmePath)) {
    New-Item -ItemType Directory -Path $traefikAcmePath -Force | Out-Null
}

# Set permissions (Windows equivalent)
try {
    $acl = Get-Acl $traefikAcmePath
    $acl.SetAccessRuleProtection($true, $false)
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($adminRule)
    $acl.SetAccessRule($systemRule)
    Set-Acl -Path $traefikAcmePath -AclObject $acl
    Write-Success "Created $traefikAcmePath directory with secure permissions"
} catch {
    Write-Warning "Created $traefikAcmePath directory (permissions might need manual adjustment)"
}

# Check if Docker is running
Write-Header "Checking Docker"
try {
    $dockerInfo = docker info 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker not accessible"
    }
    Write-Success "Docker is running"
} catch {
    Write-Error "Docker is not running or not accessible"
    exit 1
}

# Check if Compose is available
try {
    docker compose version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose not available"
    }
    Write-Success "Docker Compose is available"
} catch {
    Write-Error "Docker Compose is not available"
    exit 1
}

# Pull images
Write-Header "Pulling Images"
docker compose --profile $Profile pull
if ($LASTEXITCODE -eq 0) {
    Write-Success "Images pulled successfully"
} else {
    Write-Error "Failed to pull images"
    exit 1
}

# Start services
Write-Header "Starting Services"
docker compose --profile $Profile up -d
if ($LASTEXITCODE -eq 0) {
    Write-Success "Services started"
} else {
    Write-Error "Failed to start services"
    exit 1
}

# Wait for services to be healthy
Write-Header "Waiting for Services"
Start-Sleep -Seconds 10

# Check service status
Write-Header "Service Status"
docker compose --profile $Profile ps

# Show access information
Write-Header "Access Information"
$domain = [Environment]::GetEnvironmentVariable("DOMAIN")

Write-Host "Your homelab is ready! Access your services at:" -ForegroundColor $colors.Cyan
Write-Host "• Portainer: " -NoNewline; Write-Host "https://portainer.$domain" -ForegroundColor $colors.Green
Write-Host "• Whoami (test): " -NoNewline; Write-Host "https://whoami.$domain" -ForegroundColor $colors.Green
Write-Host "• Traefik Dashboard: " -NoNewline; Write-Host "https://traefik.$domain" -ForegroundColor $colors.Green
Write-Host ""

# Try to get public IP
try {
    $publicIP = (Invoke-RestMethod -Uri "https://ifconfig.me" -TimeoutSec 5).Trim()
    Write-Host "Make sure your DNS records point to this server:"
    Write-Host "• A/AAAA record: " -NoNewline; Write-Host "*.$domain" -ForegroundColor $colors.Yellow -NoNewline; Write-Host " -> $publicIP"
} catch {
    Write-Host "Make sure your DNS records point to this server's public IP"
}

Write-Host ""
Write-Warning "If using Cloudflare Tunnel, configure public hostnames in Zero Trust dashboard"

Write-Success "Setup completed successfully!"
