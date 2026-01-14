# Output file path
$target = "search-corp.cyber.only.sap"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "NetworkDiagnosticsForInternalLink$($timestamp).txt"



# Clear old file
"" | Out-File $OutputFile

# Write header
"Network Test Results" | Out-File $OutputFile -Append
"Date: $(Get-Date)" | Out-File $OutputFile -Append
"---------------------------" | Out-File $OutputFile -Append

# Ping
"PING search-corp.cyber.only.sap" | Out-File $OutputFile -Append
ping $target | Out-File $OutputFile -Append
"---------------------------" | Out-File $OutputFile -Append

# Traceroute
"TRACERT search-corp.cyber.only.sap" | Out-File $OutputFile -Append
tracert $target | Out-File $OutputFile -Append
"---------------------------" | Out-File $OutputFile -Append

# NSLookup
"NSLOOKUP search-corp.cyber.only.sap" | Out-File $OutputFile -Append
nslookup $target | Out-File $OutputFile -Append
"---------------------------" | Out-File $OutputFile -Append

"Test completed" | Out-File $OutputFile -Append
