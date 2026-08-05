#Requires -Version 5.1
# Pulse_Check_network.ps1
# Quick multi-target connectivity checker.
# Tests DNS resolution, IPv4 reachability (with RTT + packet loss), IPv6, and MTU
# fragmentation for every target — all in parallel using a RunspacePool.
# Output: per-target detail printed as tests finish, then a summary table.
[CmdletBinding()]
param(
    # Path to the optional JSON config file. Copy Pulse_Check_network.config.example.json
    # to Pulse_Check_network.config.json and edit it to customise targets or default MTU.
    [string]$ConfigFile = "$PSScriptRoot\Pulse_Check_network.config.json"
)

# ── Config loading ────────────────────────────────────────────────────────────
# These are the built-in targets used when no config file exists.
# Add or remove entries here if you don't want to use a config file.
$defaultTargets = @(
    "google.com","cloudflare.com","microsoft.com","amazon.in",
    "youtube.com","facebook.com","twitter.com","linkedin.com",
    "github.com","netflix.com","mausam.imd.gov.in",
    "us-east-1.console.aws.amazon.com"
)

# Try to load an optional JSON config file.
# If it exists and is valid, its "targets" and "defaultMtu" values override the
# built-in defaults above. The file is gitignored so you can store internal
# hostnames safely — see Pulse_Check_network.config.example.json for the format.
$config = $null
if (Test-Path $ConfigFile) {
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse config file; using defaults."
    }
}
# Use targets from config if present, otherwise fall back to $defaultTargets
$targets = if ($config -and $config.targets) { [string[]]$config.targets } else { $defaultTargets }

# ── Additional hostnames prompt ───────────────────────────────────────────────
# Lets you test ad-hoc hostnames or IPs without editing the script or config.
# Multiple entries are separated by commas, e.g.: sap.com, 10.0.0.1, myhost.corp
# Each entry is validated against the same safe-input pattern used across this repo.
# Press Enter to skip — the default target list runs unchanged.
Write-Host "Enter extra hostnames/IPs to test (comma-separated), or press Enter to skip:" -ForegroundColor DarkCyan
$extraInput = Read-Host "Extra targets"
if (-not [string]::IsNullOrWhiteSpace($extraInput)) {
    $extraInput -split ',' | ForEach-Object {
        $h = $_.Trim()
        # Allow only safe characters: letters, digits, dots, hyphens, colons (for IPv6)
        if ($h -match '^[a-zA-Z0-9.\-:]+$') {
            $targets += $h
        } else {
            Write-Warning "Skipping invalid hostname: '$h'"
        }
    }
}

# ── MTU prompt ────────────────────────────────────────────────────────────────
# MTU (Maximum Transmission Unit) is the largest packet size the network path
# can carry without splitting (fragmenting) it. Common values:
#   1500 — standard Ethernet
#   1460 — typical TCP payload after IP + TCP headers
#   1400 — common VPN / tunnel overhead
# The loop re-prompts until the user enters a valid integer in the range 68–9000.
$defaultMtu = if ($config -and $config.defaultMtu) { $config.defaultMtu } else { 1460 }
do {
    $mtuInput = Read-Host "Enter MTU size to test (default: $defaultMtu)"
    if ([string]::IsNullOrWhiteSpace($mtuInput)) { $mtuInput = "$defaultMtu" }
} while ($mtuInput -notmatch '^\d+$' -or [int]$mtuInput -lt 68 -or [int]$mtuInput -gt 9000)
$MTU = [int]$mtuInput

# ── Timestamp header ──────────────────────────────────────────────────────────
$runTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "`nPulse Check  —  $runTime  |  MTU: $MTU  |  Targets: $($targets.Count)" -ForegroundColor Cyan
Write-Host ("─" * 70) -ForegroundColor DarkGray

# ── RunspacePool setup ────────────────────────────────────────────────────────
# A RunspacePool lets multiple PowerShell instances run concurrently in the same
# process. Without it, 12 targets tested sequentially can take 30–60 seconds
# (network latency stacks up). With the pool all targets run in parallel and the
# total wall-clock time equals the slowest single target, typically ~5 seconds.
#
# Min threads = 1, Max threads = number of targets (capped at 8 to avoid
# flooding a slow network link with too many simultaneous pings).
$pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($targets.Count, 8))
$pool.Open()

# This script block runs inside each runspace (one per target).
# It receives the hostname/IP and MTU, performs all four tests, and returns
# a single PSCustomObject with the results. The outer script collects those
# objects once all runspaces finish and then formats the output.
$scriptBlock = {
    param([string]$Server, [int]$MTU)

    # Initialise the result object with safe "failed" defaults.
    # This way, if a test throws unexpectedly, the row still appears in the
    # summary rather than silently disappearing.
    $result = [PSCustomObject]@{
        Server     = $Server
        DnsStatus  = "FAIL"   # PASS | FAIL
        DnsAddress = ""       # resolved IPv4 address string
        IPv4Status = "FAIL"   # PASS | FAIL
        IPv4Addr   = ""
        IPv4RttMs  = -1       # average RTT in ms across 3 pings; -1 = no reply
        IPv4Loss   = 100      # packet loss percentage (0–100)
        IPv6Status = "SKIP"   # PASS | FAIL | SKIP (SKIP = no AAAA record found)
        IPv6Addr   = ""       # resolved IPv6 address string
        MtuStatus  = "FAIL"   # OK | FRAGMENT | TIMEOUT | UNREACH | FAIL
        MtuNote    = ""       # human-readable detail for non-OK statuses
    }

    # ── Test 1: DNS resolution ────────────────────────────────────────────────
    # Resolve the hostname using .NET directly so DNS is a distinct, explicit
    # step. If this fails, the host is unreachable at the name-resolution level
    # (wrong hostname, DNS outage, split-horizon DNS issue, etc.) and there is
    # no point running the remaining ping tests — we return early.
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($Server)
        # Pick the first IPv4 (InterNetwork) and IPv6 (InterNetworkV6) addresses
        $v4 = $addrs | Where-Object { $_.AddressFamily -eq 'InterNetwork' }    | Select-Object -First 1
        $v6 = $addrs | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' }  | Select-Object -First 1
        if ($v4) {
            $result.DnsStatus  = "PASS"
            $result.DnsAddress = $v4.ToString()
        }
        # Store the IPv6 address for Test 3 even if we don't mark DNS as PASS for it
        if ($v6) { $result.IPv6Addr = $v6.ToString() }
    } catch {
        $result.DnsStatus = "FAIL"
        return $result   # no IP to ping — skip remaining tests
    }

    # ── Test 2: IPv4 reachability (3 packets) ────────────────────────────────
    # Sending 3 ICMP packets instead of 1 lets us calculate a packet-loss
    # percentage. A single-packet test would report FAIL on any transient drop
    # even if the host is healthy. 3 packets is a lightweight compromise between
    # accuracy and speed.
    try {
        $ping4  = New-Object System.Net.NetworkInformation.Ping
        $opts4  = New-Object System.Net.NetworkInformation.PingOptions
        $opts4.DontFragment = $false   # allow fragmentation for this test
        $buf    = [byte[]]::new(32)    # 32-byte payload (same as default Windows ping)
        $sent   = 3; $recv = 0; $rttTotal = 0
        for ($i = 0; $i -lt $sent; $i++) {
            $r = $ping4.Send($result.DnsAddress, 2000, $buf, $opts4)   # 2000 ms timeout
            if ($r.Status -eq 'Success') {
                $recv++
                $rttTotal += $r.RoundtripTime
            }
        }
        if ($recv -gt 0) {
            $result.IPv4Status = "PASS"
            $result.IPv4Addr   = $result.DnsAddress
            $result.IPv4RttMs  = [math]::Round($rttTotal / $recv)                        # average RTT
            $result.IPv4Loss   = [math]::Round((($sent - $recv) / $sent) * 100)          # loss %
        } else {
            $result.IPv4Status = "FAIL"
            $result.IPv4Loss   = 100
        }
    } catch {
        $result.IPv4Status = "FAIL"
    }

    # ── Test 3: IPv6 reachability ─────────────────────────────────────────────
    # Only runs if DNS returned an AAAA (IPv6) record in Test 1.
    # SKIP means the host has no IPv6 address — not a problem on most networks.
    # FAIL means a record exists but the host didn't respond over IPv6, which
    # could indicate the local router or ISP doesn't forward IPv6 traffic.
    if ($result.IPv6Addr) {
        try {
            $ping6 = New-Object System.Net.NetworkInformation.Ping
            $r6    = $ping6.Send($result.IPv6Addr, 2000)
            if ($r6.Status -eq 'Success') {
                $result.IPv6Status = "PASS"
            } else {
                $result.IPv6Status = "FAIL"
            }
        } catch {
            $result.IPv6Status = "FAIL"
        }
    }
    # If $result.IPv6Addr is empty, IPv6Status stays "SKIP" (set in the default above)

    # ── Test 4: MTU / DontFragment probe ─────────────────────────────────────
    # Sends a single ICMP packet with the DF (Don't Fragment) bit set and a
    # payload sized so the total IP packet equals the requested MTU.
    #
    # Payload size = MTU - 28 bytes because:
    #   IP header  = 20 bytes
    #   ICMP header =  8 bytes
    #   Total fixed overhead = 28 bytes
    #
    # Status meanings:
    #   OK        — packet arrived intact; the path supports this MTU
    #   FRAGMENT  — a router along the path rejected the oversized packet
    #               (PacketTooBig ICMP reply); try a smaller MTU
    #   TIMEOUT   — no reply within 2 seconds; firewall may be dropping ICMP
    #   UNREACH   — destination explicitly reported it is unreachable
    #   FAIL      — unexpected .NET exception (e.g. network adapter down)
    try {
        $pingM   = New-Object System.Net.NetworkInformation.Ping
        $optsM   = New-Object System.Net.NetworkInformation.PingOptions
        $optsM.DontFragment = $true
        $payload = [byte[]]::new($MTU - 28)   # 28 = IP(20) + ICMP(8) headers
        $rM = $pingM.Send($result.DnsAddress, 2000, $payload, $optsM)
        switch ($rM.Status) {
            'Success'                { $result.MtuStatus = "OK";       $result.MtuNote = "" }
            'PacketTooBig'           { $result.MtuStatus = "FRAGMENT"; $result.MtuNote = "fragmentation required" }
            'TimedOut'               { $result.MtuStatus = "TIMEOUT";  $result.MtuNote = "no reply" }
            'DestinationUnreachable' { $result.MtuStatus = "UNREACH";  $result.MtuNote = "dest unreachable" }
            default                  { $result.MtuStatus = "FAIL";     $result.MtuNote = $rM.Status }
        }
    } catch {
        $result.MtuStatus = "FAIL"
        $result.MtuNote   = $_.Exception.Message -replace "`r`n"," "
    }

    return $result
}

# ── Dispatch jobs ─────────────────────────────────────────────────────────────
# Create one PowerShell instance per target, assign it to the shared pool,
# and start it asynchronously with BeginInvoke(). The Handle returned by
# BeginInvoke() is stored so EndInvoke() can collect the result later.
$jobs = foreach ($target in $targets) {
    $rs = [PowerShell]::Create()
    $rs.RunspacePool = $pool
    [void]$rs.AddScript($scriptBlock).AddArgument($target).AddArgument($MTU)
    [PSCustomObject]@{ PS = $rs; Handle = $rs.BeginInvoke() }
}

# ── Collect results ───────────────────────────────────────────────────────────
# EndInvoke() blocks until that particular runspace finishes, then returns its
# output. Iterating $jobs in order means we wait for the slowest target once;
# all faster targets are already done by the time we reach them.
$allResults = foreach ($job in $jobs) {
    $r = $job.PS.EndInvoke($job.Handle)
    $job.PS.Dispose()   # release the runspace memory immediately
    $r
}
# Close and dispose the pool once all jobs are collected
$pool.Close()
$pool.Dispose()

# ── Per-target detail output ──────────────────────────────────────────────────
foreach ($r in $allResults) {
    Write-Host "`n--- $($r.Server) ---" -ForegroundColor Yellow

    # DNS row — shows the resolved IP address
    $dnsColor = if ($r.DnsStatus -eq "PASS") { "Green" } else { "Red" }
    Write-Host "  DNS : $($r.DnsAddress.PadRight(40))" -NoNewline
    Write-Host "[$($r.DnsStatus)]" -ForegroundColor $dnsColor

    # IPv4 row — shows resolved IP, average RTT, and packet-loss % if non-zero
    if ($r.IPv4Status -eq "PASS") {
        $lossStr = if ($r.IPv4Loss -eq 0) { "" } else { "  loss:$($r.IPv4Loss)%" }
        Write-Host "  IPv4: $($r.IPv4Addr.PadRight(40))" -NoNewline
        Write-Host "[PASS]  RTT: $($r.IPv4RttMs) ms$lossStr" -ForegroundColor Green
    } else {
        Write-Host "  IPv4: (unreachable)".PadRight(44) -NoNewline
        Write-Host "[FAIL]" -ForegroundColor Red
    }

    # IPv6 row — gray for SKIP (no record), red for FAIL (record exists but no reply)
    $v6Color = switch ($r.IPv6Status) { "PASS" { "Green" } "FAIL" { "Red" } default { "DarkGray" } }
    $v6Label = if ($r.IPv6Addr) { $r.IPv6Addr } else { "(no AAAA record)" }
    Write-Host "  IPv6: $($v6Label.PadRight(40))" -NoNewline
    Write-Host "[$($r.IPv6Status)]" -ForegroundColor $v6Color

    # MTU row — magenta for fragmentation (needs smaller MTU), dark yellow for timeout
    $mtuColor = switch ($r.MtuStatus) {
        "OK"       { "Green"       }
        "FRAGMENT" { "Magenta"     }
        "TIMEOUT"  { "DarkYellow"  }
        default    { "Red"         }
    }
    $mtuDetail = if ($r.MtuNote) { "  ($($r.MtuNote))" } else { "" }
    Write-Host "  MTU : ($MTU bytes)".PadRight(44) -NoNewline
    Write-Host "[$($r.MtuStatus)]$mtuDetail" -ForegroundColor $mtuColor
}

# ── Summary table ─────────────────────────────────────────────────────────────
# One row per target showing all four test results side-by-side.
# Rows are white for overall PASS (IPv4 reachable) and red for FAIL.
# The final line shows a quick passed/failed/total count.
Write-Host "`n$("─" * 70)" -ForegroundColor DarkGray
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host ("  {0,-35} {1,-6} {2,-6} {3,-6} {4,-10}" -f "Target","DNS","IPv4","IPv6","MTU")
Write-Host ("  {0,-35} {1,-6} {2,-6} {3,-6} {4,-10}" -f ("─"*34),("─"*5),("─"*5),("─"*5),("─"*9))

$passCount = 0; $failCount = 0
foreach ($r in $allResults) {
    $dnsS  = $r.DnsStatus.PadRight(6)
    $v4S   = $r.IPv4Status.PadRight(6)
    $v6S   = $r.IPv6Status.PadRight(6)
    $mtuS  = $r.MtuStatus.PadRight(10)
    $rtt   = if ($r.IPv4RttMs -ge 0) { "$($r.IPv4RttMs)ms" } else { "" }
    $line  = "  {0,-35} {1,-6} {2,-6} {3,-6} {4,-10} {5}" -f $r.Server,$dnsS,$v4S,$v6S,$mtuS,$rtt
    $color = if ($r.IPv4Status -eq "PASS") { $passCount++; "White" } else { $failCount++; "Red" }
    Write-Host $line -ForegroundColor $color
}

Write-Host "`n  Passed: $passCount  |  Failed: $failCount  |  Total: $($allResults.Count)" -ForegroundColor Cyan
Write-Host ("─" * 70) -ForegroundColor DarkGray

Write-Host "`nAll tests complete. Press any key to exit..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
