<#
.SYNOPSIS
    Sends multiple ICMP pings to one or more hosts simultaneously and reports latency statistics.

.DESCRIPTION
    Pings all hostnames/IPs in parallel using a RunspacePool — one runspace per host.
    Collects round-trip times, calculates packet loss and latency stats (min/max/avg),
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

# ── Scriptblock: runs inside each runspace (one per host) ─────────────────────
# Receives all inputs as parameters — runspaces have no access to the parent scope.
$pingScriptBlock = {
    param(
        [string]$Hostname,
        [int]$Count,
        [int]$TimeoutMS,
        [int]$DelayMS
    )

    # Per-host stats object
    # MinTime starts at MaxValue so the first real reply always wins the comparison
    $stats = [PSCustomObject]@{
        Hostname    = $Hostname
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
            $stats.Sent++

            try {
                # Core ping — blocks until reply arrives or TimeoutMS expires
                $reply = $ping.Send($Hostname, $TimeoutMS)

                if ($reply.Status -eq 'Success') {
                    $stats.Received++
                    $responseTimes.Add($reply.RoundtripTime)

                    # Update running min/max inline — no second pass needed
                    if ($reply.RoundtripTime -lt $stats.MinTime) { $stats.MinTime = $reply.RoundtripTime }
                    if ($reply.RoundtripTime -gt $stats.MaxTime) { $stats.MaxTime = $reply.RoundtripTime }
                }
                # Status != Success (e.g. TimedOut, DestinationHostUnreachable) counts as lost
            } catch {
                # Deduplicate errors: only store each unique message once
                $msg = $_.Exception.Message
                if (-not $stats.Errors.Contains($msg)) { $stats.Errors.Add($msg) }
            }

            # Optional inter-ping delay to avoid flooding or triggering rate limits
            if ($DelayMS -gt 0) { Start-Sleep -Milliseconds $DelayMS }
        }
    } finally {
        $ping.Dispose()
    }

    # ── Calculate final statistics ────────────────────────────────────────────
    $stats.Lost        = $Count - $stats.Received
    $stats.LossPercent = [Math]::Round(($stats.Lost     / $Count) * 100, 2)
    $stats.SuccessRate = [Math]::Round(($stats.Received / $Count) * 100, 2)

    if ($responseTimes.Count -gt 0) {
        $stats.AvgTime = [Math]::Round(($responseTimes | Measure-Object -Average).Average, 2)
    } else {
        # No successful replies — reset sentinel so 0 displays instead of [int]::MaxValue
        $stats.MinTime = 0
    }

    return $stats
}

# ── Function: Invoke-MassPing ─────────────────────────────────────────────────
# Creates a RunspacePool and fires one runspace per host simultaneously.
# Waits for all to finish, then collects and returns results in original input order.
function Invoke-MassPing {
    param(
        [string[]]$Hosts,
        [int]$Count,
        [int]$TimeoutMS,
        [int]$DelayMS,
        [bool]$ShowProgress,
        [scriptblock]$WorkerScript
    )

    $totalHosts = $Hosts.Count

    # Pool size = number of hosts — every host pings concurrently
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $totalHosts)
    $pool.Open()

    # Launch one PowerShell instance per host and track its async handle
    $jobs = foreach ($hostname in $Hosts) {
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        $ps.AddScript($WorkerScript)       | Out-Null
        $ps.AddParameter('Hostname',   $hostname)  | Out-Null
        $ps.AddParameter('Count',      $Count)     | Out-Null
        $ps.AddParameter('TimeoutMS',  $TimeoutMS) | Out-Null
        $ps.AddParameter('DelayMS',    $DelayMS)   | Out-Null

        [PSCustomObject]@{
            Hostname = $hostname
            PS       = $ps
            Handle   = $ps.BeginInvoke()   # starts running immediately in the background
        }
    }

    Write-Host "All $totalHosts hosts pinging simultaneously...`n" -ForegroundColor Cyan

    # Poll until every runspace has finished, showing a live progress bar
    if ($ShowProgress) {
        while ($jobs | Where-Object { -not $_.Handle.IsCompleted }) {
            $done = ($jobs | Where-Object { $_.Handle.IsCompleted }).Count
            Write-Progress -Activity 'Parallel Ping' `
                -Status "$done / $totalHosts hosts completed" `
                -PercentComplete (($done / $totalHosts) * 100)
            Start-Sleep -Milliseconds 500
        }
        Write-Progress -Activity 'Parallel Ping' -Completed
    } else {
        # No progress bar — just block until all handles signal completion
        $jobs | ForEach-Object { $_.Handle.AsyncWaitHandle.WaitOne() | Out-Null }
    }

    # Collect results in original input order so the summary matches the input list
    $results = [ordered]@{}
    foreach ($job in $jobs) {
        $stats = $job.PS.EndInvoke($job.Handle)[0]   # [0] unwraps the PSDataCollection wrapper EndInvoke returns

        # Print per-host summary as each result is collected
        $lossColor    = if ($stats.Lost -gt 0)         { 'Red'   } else { 'Green'  }
        $successColor = if ($stats.SuccessRate -eq 100) { 'Green' } else { 'Yellow' }

        Write-Host "--- Summary for $($stats.Hostname) ---"                                          -ForegroundColor Yellow
        Write-Host "  Sent:        $($stats.Sent)"                                                   -ForegroundColor White
        Write-Host "  Received:    $($stats.Received)"                                               -ForegroundColor Green
        Write-Host "  Lost:        $($stats.Lost)"                                                   -ForegroundColor $lossColor
        Write-Host "  Loss %:      $($stats.LossPercent)%"                                           -ForegroundColor $lossColor
        Write-Host "  Min/Max/Avg: $($stats.MinTime)ms / $($stats.MaxTime)ms / $($stats.AvgTime)ms"  -ForegroundColor White
        Write-Host "  Success:     $($stats.SuccessRate)%`n"                                         -ForegroundColor $successColor

        if ($stats.Errors.Count -gt 0) {
            Write-Host "  Errors ($($stats.Errors.Count) unique):" -ForegroundColor Red
            $stats.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkRed }
        }

        $job.PS.Dispose()
        $results[$stats.Hostname] = $stats
    }

    $pool.Close()
    $pool.Dispose()

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

    Write-Host "Results exported to: $FilePath" -ForegroundColor Green
}

# ── Main ──────────────────────────────────────────────────────────────────────

$sep = '=' * 40

# Print run configuration upfront so the user can cancel early if something looks wrong
Write-Host $sep                                               -ForegroundColor Cyan
Write-Host 'Mass Ping Utility (Parallel)'                    -ForegroundColor Cyan
Write-Host $sep                                               -ForegroundColor Cyan
Write-Host "Hostnames:   $($Hostnames -join ', ')"           -ForegroundColor White
Write-Host "Pings/Host:  $PingCount"                         -ForegroundColor White
Write-Host "Timeout:     ${Timeout}ms"                       -ForegroundColor White
Write-Host "Delay:       ${DelayMs}ms"                       -ForegroundColor White
Write-Host "Total Pings: $($Hostnames.Count * $PingCount)"   -ForegroundColor White
Write-Host "$sep`n"                                           -ForegroundColor Cyan

# Run all hosts in parallel and measure total wall-clock time
$startTime = Get-Date
$results   = Invoke-MassPing -Hosts $Hostnames -Count $PingCount -TimeoutMS $Timeout `
                              -DelayMS $DelayMs -ShowProgress (-not $NoProgressBar) `
                              -WorkerScript $pingScriptBlock
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
