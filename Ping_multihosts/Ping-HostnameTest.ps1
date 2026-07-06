<#
.SYNOPSIS
    Sends multiple ICMP pings to one or more hosts and reports latency statistics.

.DESCRIPTION
    Pings each hostname/IP a configurable number of times using the .NET Ping class,
    collects round-trip times, calculates packet loss and latency stats (min/max/avg),
    prints a per-host and overall summary to the console, and saves results to a CSV.

.PARAMETER Hostnames
    One or more hostnames or IP addresses to ping. Defaults to 4 public targets.

.PARAMETER PingCount
    Number of ICMP echo requests to send per host. Default: 1000.

.PARAMETER Timeout
    Maximum wait time in milliseconds for each ping reply. Default: 5000ms.

.PARAMETER DelayMs
    Pause in milliseconds between each ping. Useful to avoid rate-limiting. Default: 0.

.PARAMETER OutputCSV
    Path for the CSV output file. Defaults to a timestamped file in the script's folder.

.PARAMETER NoProgressBar
    Suppress the Write-Progress bar (useful in non-interactive/CI environments).

.EXAMPLE
    .\Ping-HostnameTest.ps1

.EXAMPLE
    .\Ping-HostnameTest.ps1 -Hostnames "8.8.8.8","10.0.0.1" -PingCount 500

.EXAMPLE
    .\Ping-HostnameTest.ps1 -Hostnames "8.8.8.8" -DelayMs 50 -OutputCSV "C:\Reports\ping.csv"
#>

param(
    [string[]]$Hostnames = @("google.com", "cloudflare.com", "1.1.1.1", "8.8.8.8"),
    [int]$PingCount      = 1000,
    [int]$Timeout        = 5000,
    [int]$DelayMs        = 0,
    # Auto-generates a timestamped CSV next to the script if no path is provided
    [string]$OutputCSV   = (Join-Path $PSScriptRoot "PingResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"),
    [switch]$NoProgressBar
)

# ── Input Validation ──────────────────────────────────────────────────────────
# Block characters that could be used for command injection via hostname input
$hostnamePattern = '^[a-zA-Z0-9.\-:]+$'
foreach ($h in $Hostnames) {
    if ($h -notmatch $hostnamePattern) {
        Write-Error "Invalid hostname: '$h'. Only alphanumeric, dots, hyphens, and colons are allowed."
        exit 1
    }
}

# ── Function: Invoke-MassPing ─────────────────────────────────────────────────
# Loops over every host, pings it $Count times, and returns an ordered hashtable
# keyed by hostname, each value being a stats PSCustomObject.
function Invoke-MassPing {
    param(
        [string[]]$Hosts,
        [int]$Count,
        [int]$TimeoutMS,
        [int]$DelayMS,
        [bool]$ShowProgress
    )

    # Ordered so results print in the same order the user specified hosts
    $results     = [ordered]@{}
    $totalHosts  = $Hosts.Count
    $currentHost = 0

    foreach ($hostname in $Hosts) {
        $currentHost++

        if ($ShowProgress) {
            Write-Host "[$currentHost/$totalHosts] Processing: $hostname" -ForegroundColor Cyan
        }

        # Per-host stats object — reset fresh for every host
        # MinTime starts at MaxValue so the first real reply always wins the comparison
        $stats = [PSCustomObject]@{
            Hostname    = $hostname
            Sent        = 0
            Received    = 0
            Lost        = 0
            LossPercent = 0.0
            MinTime     = [int]::MaxValue
            MaxTime     = 0
            AvgTime     = 0.0
            SuccessRate = 0.0
            Errors      = [System.Collections.Generic.List[string]]::new()  # unique errors only
        }

        # List[long] avoids the O(n²) cost of PowerShell's += on plain arrays
        $responseTimes = [System.Collections.Generic.List[long]]::new()
        $ping          = New-Object System.Net.NetworkInformation.Ping

        try {
            for ($i = 1; $i -le $Count; $i++) {

                # Update progress bar every 100 pings to avoid excessive UI overhead
                if ($ShowProgress -and ($i % 100 -eq 0)) {
                    Write-Progress -Activity "Pinging $hostname ($currentHost/$totalHosts)" `
                        -Status "Ping $i / $Count" `
                        -PercentComplete (($i / $Count) * 100) -Id 1
                }

                $stats.Sent++

                try {
                    # Core ping — blocks until reply arrives or TimeoutMS expires
                    $reply = $ping.Send($hostname, $TimeoutMS)

                    if ($reply.Status -eq 'Success') {
                        $stats.Received++
                        $responseTimes.Add($reply.RoundtripTime)

                        # Update running min/max inline — no second pass needed
                        if ($reply.RoundtripTime -lt $stats.MinTime) { $stats.MinTime = $reply.RoundtripTime }
                        if ($reply.RoundtripTime -gt $stats.MaxTime) { $stats.MaxTime = $reply.RoundtripTime }
                    }
                    # Status != Success (e.g. TimedOut, DestinationHostUnreachable) counts as lost — no action needed
                } catch {
                    # Deduplicate errors: only store each unique message once
                    $msg = $_.Exception.Message
                    if (-not $stats.Errors.Contains($msg)) { $stats.Errors.Add($msg) }
                }

                # Optional inter-ping delay to avoid flooding or triggering rate limits
                if ($DelayMS -gt 0) { Start-Sleep -Milliseconds $DelayMS }
            }
        } finally {
            # Always clear the progress bar and dispose the socket,
            # even if an exception interrupted the loop
            if ($ShowProgress) { Write-Progress -Activity "Pinging $hostname" -Completed -Id 1 }
            $ping.Dispose()
        }

        # ── Calculate final statistics ────────────────────────────────────────
        $stats.Lost        = $Count - $stats.Received
        $stats.LossPercent = [Math]::Round(($stats.Lost     / $Count) * 100, 2)
        $stats.SuccessRate = [Math]::Round(($stats.Received / $Count) * 100, 2)

        if ($responseTimes.Count -gt 0) {
            $stats.AvgTime = [Math]::Round(($responseTimes | Measure-Object -Average).Average, 2)
        } else {
            # No successful replies — reset sentinel so 0 displays instead of [int]::MaxValue
            $stats.MinTime = 0
        }

        # ── Per-host console summary ──────────────────────────────────────────
        $lossColor    = if ($stats.Lost -gt 0)         { 'Red'   } else { 'Green'  }
        $successColor = if ($stats.SuccessRate -eq 100) { 'Green' } else { 'Yellow' }

        Write-Host "`n--- Summary for $hostname ---"                                                 -ForegroundColor Yellow
        Write-Host "  Sent:        $($stats.Sent)"                                                  -ForegroundColor White
        Write-Host "  Received:    $($stats.Received)"                                              -ForegroundColor Green
        Write-Host "  Lost:        $($stats.Lost)"                                                  -ForegroundColor $lossColor
        Write-Host "  Loss %:      $($stats.LossPercent)%"                                          -ForegroundColor $lossColor
        Write-Host "  Min/Max/Avg: $($stats.MinTime)ms / $($stats.MaxTime)ms / $($stats.AvgTime)ms" -ForegroundColor White
        Write-Host "  Success:     $($stats.SuccessRate)%"                                          -ForegroundColor $successColor

        if ($stats.Errors.Count -gt 0) {
            Write-Host "  Errors ($($stats.Errors.Count) unique):" -ForegroundColor Red
            $stats.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkRed }
        }

        $results[$hostname] = $stats
    }

    return $results
}

# ── Function: Export-ResultsToCSV ─────────────────────────────────────────────
# Writes the stats hashtable to a CSV file. Creates the output directory if needed.
function Export-ResultsToCSV {
    param(
        $Results,
        [string]$FilePath
    )

    # Auto-create output directory if it doesn't exist (e.g. first run with custom path)
    $dir = Split-Path $FilePath -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Rename MinTime/MaxTime/AvgTime → *_ms and flatten Errors list to a count
    $Results.Values | Select-Object Hostname, Sent, Received, Lost, LossPercent,
        @{N = 'MinTime_ms';   E = { $_.MinTime }},
        @{N = 'MaxTime_ms';   E = { $_.MaxTime }},
        @{N = 'AvgTime_ms';   E = { $_.AvgTime }},
        SuccessRate,
        @{N = 'UniqueErrors'; E = { $_.Errors.Count }} |
        Export-Csv -Path $FilePath -NoTypeInformation -Force   # -Force overwrites existing file

    Write-Host "`nResults exported to: $FilePath" -ForegroundColor Green
}

# ── Main ──────────────────────────────────────────────────────────────────────

$sep = '=' * 40

# Print run configuration upfront so the user can cancel early if something looks wrong
Write-Host $sep                                               -ForegroundColor Cyan
Write-Host 'Mass Ping Utility'                               -ForegroundColor Cyan
Write-Host $sep                                               -ForegroundColor Cyan
Write-Host "Hostnames:   $($Hostnames -join ', ')"           -ForegroundColor White
Write-Host "Pings/Host:  $PingCount"                         -ForegroundColor White
Write-Host "Timeout:     ${Timeout}ms"                       -ForegroundColor White
Write-Host "Delay:       ${DelayMs}ms"                       -ForegroundColor White
Write-Host "Total Pings: $($Hostnames.Count * $PingCount)"   -ForegroundColor White
Write-Host "$sep`n"                                           -ForegroundColor Cyan

# Run all pings and measure total wall-clock time
$startTime = Get-Date
$results   = Invoke-MassPing -Hosts $Hostnames -Count $PingCount -TimeoutMS $Timeout `
                              -DelayMS $DelayMs -ShowProgress (-not $NoProgressBar)
$duration  = (Get-Date) - $startTime

# ── Overall summary across all hosts ─────────────────────────────────────────
$totalSent     = ($results.Values | Measure-Object -Property Sent     -Sum).Sum
$totalReceived = ($results.Values | Measure-Object -Property Received -Sum).Sum

# Guard against division-by-zero if every ping failed before being sent
$overallLoss = if ($totalSent -gt 0) {
    [Math]::Round((($totalSent - $totalReceived) / $totalSent) * 100, 2)
} else { 0 }

Write-Host "`n$sep"                                                         -ForegroundColor Cyan
Write-Host 'OVERALL SUMMARY'                                                -ForegroundColor Cyan
Write-Host $sep                                                              -ForegroundColor Cyan
Write-Host "Duration:       $([Math]::Round($duration.TotalSeconds, 2))s"  -ForegroundColor White
Write-Host "Hosts Tested:   $($results.Count)"                             -ForegroundColor White
Write-Host "Total Sent:     $totalSent"                                     -ForegroundColor White
Write-Host "Total Received: $totalReceived"                                 -ForegroundColor Green
Write-Host "Overall Loss:   $overallLoss%" -ForegroundColor $(if ($overallLoss -gt 0) { 'Red' } else { 'Green' })
Write-Host "$sep`n"                                                          -ForegroundColor Cyan

# Always export — file path defaults to a timestamped CSV next to the script
Export-ResultsToCSV -Results $results -FilePath $OutputCSV
