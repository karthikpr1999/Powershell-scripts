# Output file path
$target = "google.com"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "Network_External_Link$($timestamp).txt"



# Clear old file
"" | Out-File $OutputFile

# Write header
"Network Test Results" | Out-File $OutputFile -Append
"Date: $(Get-Date)" | Out-File $OutputFile -Append
"---------------------------" | Out-File $OutputFile -Append

# Ping
"PING google.com" | Out-File $OutputFile -Append
ping $target | Out-File $OutputFile -Append
"---------------------------" | Out-File $OutputFile -Append

# Traceroute
"TRACERT google.com" | Out-File $OutputFile -Append
tracert $target | Out-File $OutputFile -Append
"---------------------------" | Out-File $OutputFile -Append

# NSLookup
"NSLOOKUP google.com" | Out-File $OutputFile -Append
nslookup $target | Out-File $OutputFile -Append
"---------------------------" | Out-File $OutputFile -Append

"Test completed" | Out-File $OutputFile -Append
