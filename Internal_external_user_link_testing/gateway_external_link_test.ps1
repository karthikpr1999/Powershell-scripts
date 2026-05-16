param(
    [string]$Target = "google.com",
    [string]$OutputDir = $PSScriptRoot
)

Add-Type -AssemblyName System.Windows.Forms

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDir "Network_External_Link_$timestamp.txt"

function Write-Section {
    param([string]$Text)
    $Text | Add-Content -Path $outputFile
    "---------------------------" | Add-Content -Path $outputFile
}

# Header
@(
    "Network Test Results",
    "Date: $(Get-Date)",
    "Target: $Target",
    "---------------------------"
) | Add-Content -Path $outputFile

# Ping
Write-Host "Running ping..."
"PING $Target" | Add-Content -Path $outputFile
try   { ping $Target 2>&1 | Add-Content -Path $outputFile }
catch { "ERROR: $_" | Add-Content -Path $outputFile }
"---------------------------" | Add-Content -Path $outputFile

# Traceroute (max 30 hops, 1000ms timeout per hop)
Write-Host "Running tracert..."
"TRACERT $Target" | Add-Content -Path $outputFile
try   { tracert -h 30 -w 1000 $Target 2>&1 | Add-Content -Path $outputFile }
catch { "ERROR: $_" | Add-Content -Path $outputFile }
"---------------------------" | Add-Content -Path $outputFile

# NSLookup
Write-Host "Running nslookup..."
"NSLOOKUP $Target" | Add-Content -Path $outputFile
try   { nslookup $Target 2>&1 | Add-Content -Path $outputFile }
catch { "ERROR: $_" | Add-Content -Path $outputFile }
"---------------------------" | Add-Content -Path $outputFile

"Test completed at $(Get-Date)" | Add-Content -Path $outputFile

Write-Host "Done. Results saved to: $outputFile"
