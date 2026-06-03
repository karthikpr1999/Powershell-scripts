# Ask for input
$Target = (Read-Host "Enter hostname or IP address").Trim()

# Validate: allow only hostnames and IPv4/IPv6 addresses — no shell metacharacters
if ($Target -notmatch '^[a-zA-Z0-9.\-:]+$' -or $Target.Length -eq 0) {
    Write-Error "Invalid hostname or IP address. Only alphanumeric characters, dots, hyphens, and colons are allowed."
    exit 1
}

# Output file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "NetworkDiagnosticsForLink$($timestamp).txt"

# Clear old content
"" | Out-File $OutputFile

# Header
"Network Test Results" | Out-File $OutputFile -Append
"Target: $Target" | Out-File $OutputFile -Append
"Date: $(Get-Date)" | Out-File $OutputFile -Append
"--------------------------------" | Out-File $OutputFile -Append

# Ping
"PING $Target" | Out-File $OutputFile -Append
ping $Target | Out-File $OutputFile -Append
"--------------------------------" | Out-File $OutputFile -Append

# Traceroute
"TRACERT $Target" | Out-File $OutputFile -Append
tracert $Target | Out-File $OutputFile -Append
"--------------------------------" | Out-File $OutputFile -Append

# NSLookup
"NSLOOKUP $Target" | Out-File $OutputFile -Append
nslookup $Target | Out-File $OutputFile -Append
"--------------------------------" | Out-File $OutputFile -Append

"Test completed" | Out-File $OutputFile -Append
