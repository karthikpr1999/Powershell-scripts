# Ask for input
$Target = Read-Host "Enter hostname or IP address"

# Output file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "Network_user_Link$($timestamp).txt"

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
