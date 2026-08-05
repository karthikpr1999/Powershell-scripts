#Requires -Version 5.1
# NSLookup_multi.ps1
# Run DNS lookups AND a verbose curl request for multiple URLs in parallel.
# DNS: queries A, AAAA, CNAME, MX, TXT, PTR record types per hostname.
# Curl: captures full verbose output (headers, TLS handshake, timing) per URL.
# Results: per-URL detail section followed by a summary table.

# ── DNS server prompt ─────────────────────────────────────────────────────────
# Leave blank to use the system's configured DNS.
# Enter an IPv4 address (e.g. 8.8.8.8) to query a specific server instead.
Write-Host "Enter DNS server IP to use (e.g. 8.8.8.8), or press Enter for system DNS:" -ForegroundColor DarkCyan
$dnsInput = (Read-Host "DNS server").Trim()

# Validate the DNS server IP if one was provided
if ($dnsInput -ne "" -and $dnsInput -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    Write-Warning "Invalid IP address '$dnsInput' — falling back to system DNS."
    $dnsInput = ""
}
$DnsServer  = $dnsInput   # empty string = use system DNS throughout
$DnsDisplay = if ($DnsServer) { $DnsServer } else { "system" }

# ── URL / hostname prompt ─────────────────────────────────────────────────────
# Accepts full URLs (https://google.com/search?q=1) or plain hostnames/IPs.
# [System.Uri] strips scheme, port, path, and query — only the hostname is used.
#
# Input modes (both work):
#   • Paste one URL per line — press Enter on a blank line when done
#   • Type/paste multiple entries on one line separated by commas
#
# The prompt repeats until at least one valid hostname is collected.
$targets = @()      # stores (OriginalInput, Hostname) pairs for display
do {
    Write-Host "Enter URLs or hostnames (one per line, or comma-separated)." -ForegroundColor DarkCyan
    Write-Host "Press Enter on a blank line when done." -ForegroundColor DarkGray
    Write-Host "  e.g.  https://google.com/path" -ForegroundColor DarkGray
    Write-Host "        github.com" -ForegroundColor DarkGray
    Write-Host "        8.8.8.8" -ForegroundColor DarkGray

    # Collect lines until the user submits a blank line
    $lines = @()
    while ($true) {
        $line = Read-Host "  >"
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $lines += $line
    }

    # Split each line on commas too, so both input styles work
    $rawEntries = $lines | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } |
                  Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $rawEntries | ForEach-Object {
        $raw = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return }

        # Try to parse as a URI first (handles http://, https://, ftp://, etc.)
        $hostname = $null
        if ($raw -match '^\w+://') {
            # Looks like a full URL — let .NET parse it
            try {
                $uri = [System.Uri]$raw
                $hostname = $uri.Host   # strips scheme, port, path, query
            } catch {
                Write-Warning "Could not parse URL '$raw' — skipping."
                return
            }
        } else {
            # No scheme — treat as a plain hostname or IP.
            # Add a temporary scheme so [System.Uri] can still parse it cleanly
            # and strip any accidental path/query the user may have included.
            try {
                $uri = [System.Uri]("http://" + $raw)
                $hostname = $uri.Host
            } catch {
                $hostname = $raw   # fall back to the raw string as-is
            }
        }

        if ([string]::IsNullOrWhiteSpace($hostname)) {
            Write-Warning "Could not extract a hostname from '$raw' — skipping."
            return
        }

        # Validate the extracted hostname against the safe-input pattern
        if ($hostname -match '^[a-zA-Z0-9.\-:]+$') {
            $targets += [PSCustomObject]@{ Original = $raw; Hostname = $hostname }
        } else {
            Write-Warning "Skipping invalid hostname '$hostname' (from '$raw')"
        }
    }

    if ($targets.Count -eq 0) {
        Write-Warning "No valid targets entered. Please try again."
    }
} while ($targets.Count -eq 0)

# ── Timestamp header ──────────────────────────────────────────────────────────
$runTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "`nNSLookup Multi  —  $runTime  |  DNS: $DnsDisplay  |  Targets: $($targets.Count)" -ForegroundColor Cyan
Write-Host ("─" * 70) -ForegroundColor DarkGray

# ── RunspacePool setup ────────────────────────────────────────────────────────
# Two runspaces per target (one DNS, one curl) run concurrently.
# Capped at 16 threads to avoid overwhelming the DNS server or network.
$pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($targets.Count * 2, 16))
$pool.Open()

# Script block executed inside each runspace — one per hostname.
# Returns a single PSCustomObject with results for all six record types.
$scriptBlock = {
    param([string]$Hostname, [string]$DnsServer)

    # Helper: build a standard record result object
    function Make-Record([string]$Status, [string[]]$Values) {
        [PSCustomObject]@{ Status = $Status; Values = $Values }
    }

    # Initialise result with FAIL defaults so any unexpected throw still produces
    # a visible row in the output rather than a silent gap.
    $result = [PSCustomObject]@{
        Hostname  = $Hostname
        DnsServer = if ($DnsServer) { $DnsServer } else { "system" }
        A         = Make-Record "FAIL" @()
        AAAA      = Make-Record "FAIL" @()
        CNAME     = Make-Record "FAIL" @()
        MX        = Make-Record "FAIL" @()
        TXT       = Make-Record "FAIL" @()
        PTR       = Make-Record "FAIL" @()
    }

    # Build the common Resolve-DnsName argument block.
    # -Server is only added when a custom DNS server was specified.
    $baseArgs = @{ ErrorAction = "SilentlyContinue" }
    if ($DnsServer) { $baseArgs["Server"] = $DnsServer }

    # ── A record (IPv4) ───────────────────────────────────────────────────────
    # Also used as the base address for the PTR lookup below.
    $aIp = $null
    try {
        $r = Resolve-DnsName -Name $Hostname -Type A @baseArgs
        $aRecs = @($r | Where-Object { $_.Type -eq "A" })
        if ($aRecs.Count -gt 0) {
            $aIp              = $aRecs[0].IPAddress   # used for PTR lookup later
            $result.A         = Make-Record "PASS" ($aRecs | ForEach-Object { $_.IPAddress })
        } else {
            $result.A         = Make-Record "NONE" @()
        }
    } catch {
        $result.A = Make-Record "FAIL" @()
    }

    # ── AAAA record (IPv6) ────────────────────────────────────────────────────
    try {
        $r = Resolve-DnsName -Name $Hostname -Type AAAA @baseArgs
        $aaaaRecs = @($r | Where-Object { $_.Type -eq "AAAA" })
        $result.AAAA = if ($aaaaRecs.Count -gt 0) {
            Make-Record "PASS" ($aaaaRecs | ForEach-Object { $_.IPAddress })
        } else {
            Make-Record "NONE" @()
        }
    } catch {
        $result.AAAA = Make-Record "FAIL" @()
    }

    # ── CNAME record ──────────────────────────────────────────────────────────
    # A CNAME is an alias pointing to another hostname. Not all hosts have one.
    try {
        $r = Resolve-DnsName -Name $Hostname -Type CNAME @baseArgs
        $cnameRecs = @($r | Where-Object { $_.Type -eq "CNAME" })
        $result.CNAME = if ($cnameRecs.Count -gt 0) {
            Make-Record "PASS" ($cnameRecs | ForEach-Object { $_.NameHost })
        } else {
            Make-Record "NONE" @()
        }
    } catch {
        $result.CNAME = Make-Record "FAIL" @()
    }

    # ── MX record (mail exchange) ─────────────────────────────────────────────
    # Shows which mail servers handle email for the domain, and their priority.
    # Lower priority number = higher preference.
    try {
        $r = Resolve-DnsName -Name $Hostname -Type MX @baseArgs
        $mxRecs = @($r | Where-Object { $_.Type -eq "MX" })
        $result.MX = if ($mxRecs.Count -gt 0) {
            $vals = $mxRecs | ForEach-Object { "$($_.NameExchange) (pri $($_.Preference))" }
            Make-Record "PASS" $vals
        } else {
            Make-Record "NONE" @()
        }
    } catch {
        $result.MX = Make-Record "FAIL" @()
    }

    # ── TXT record ────────────────────────────────────────────────────────────
    # Used for SPF, DKIM, DMARC, domain verification tokens, etc.
    # TXT records can contain multiple strings; they are joined into one line.
    try {
        $r = Resolve-DnsName -Name $Hostname -Type TXT @baseArgs
        $txtRecs = @($r | Where-Object { $_.Type -eq "TXT" })
        $result.TXT = if ($txtRecs.Count -gt 0) {
            $vals = $txtRecs | ForEach-Object { ($_.Strings -join " ") }
            Make-Record "PASS" $vals
        } else {
            Make-Record "NONE" @()
        }
    } catch {
        $result.TXT = Make-Record "FAIL" @()
    }

    # ── PTR record (reverse DNS) ──────────────────────────────────────────────
    # PTR maps an IP address back to a hostname (reverse lookup).
    # We query the resolved A record IP, not the original hostname string,
    # because PTR queries must be on an IP address.
    # If A lookup failed, PTR is skipped (no IP to reverse-look up).
    if ($aIp) {
        try {
            $r = Resolve-DnsName -Name $aIp -Type PTR @baseArgs
            $ptrRecs = @($r | Where-Object { $_.Type -eq "PTR" })
            $result.PTR = if ($ptrRecs.Count -gt 0) {
                Make-Record "PASS" ($ptrRecs | ForEach-Object { $_.NameHost })
            } else {
                Make-Record "NONE" @()
            }
        } catch {
            $result.PTR = Make-Record "FAIL" @()
        }
    } else {
        # No A record resolved — PTR has nothing to work with
        $result.PTR = Make-Record "SKIP" @()
    }

    return $result
}

# Script block executed inside each runspace for the curl verbose request.
# Uses curl.exe (ships with Windows 10 1803+) with:
#   -v          verbose — prints TLS handshake, request/response headers to stderr
#   -s          silent — suppresses the progress bar
#   -o NUL      discard the response body (we only want the verbose info)
#   -m 15       15-second max timeout
#   -L          follow redirects
#   --no-progress-meter   suppress the progress meter (redundant with -s but explicit)
# curl writes verbose lines to stderr; we redirect stderr to stdout (2>&1) so
# PowerShell can capture it — then split the combined output back into stderr
# (verbose) and stdout (body, discarded) lines by the leading "  % " marker curl
# uses for progress (absent here since -s suppresses it).
# Returns a PSCustomObject: { Url; HttpStatus; VerboseLines; ErrorMsg }
$curlScriptBlock = {
    param([string]$Url)

    $curlResult = [PSCustomObject]@{
        Url          = $Url
        HttpStatus   = ""     # e.g. "200 OK", "301 Moved", or "ERROR"
        VerboseLines = @()    # all verbose lines curl wrote to stderr
        ErrorMsg     = ""     # set if curl.exe is missing or threw
    }

    # Confirm curl.exe is available (ships with Windows 10 1803+; also present
    # if Git for Windows is installed). We call curl.exe explicitly to avoid
    # invoking the PowerShell Invoke-WebRequest alias named "curl".
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        $curlResult.ErrorMsg = "curl.exe not found on PATH"
        return $curlResult
    }

    try {
        # Run curl and capture all output (stderr merged into stdout via 2>&1).
        # -s + -o NUL means the only stdout lines are the verbose stderr ones.
        $raw = & curl.exe -v -s -L -m 15 --no-progress-meter -o NUL $Url 2>&1

        # $raw is a mix of [string] (stdout) and [System.Management.Automation.ErrorRecord]
        # (stderr) objects when using 2>&1 in PowerShell. Normalise both to strings.
        $lines = $raw | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.Exception.Message
            } else {
                "$_"
            }
        }

        $curlResult.VerboseLines = $lines

        # Extract the HTTP status from a line like "< HTTP/1.1 200 OK"
        $statusLine = $lines | Where-Object { $_ -match '^[<*]\s*HTTP/' } | Select-Object -Last 1
        if ($statusLine -match 'HTTP/[\d.]+ (\d+ .+)') {
            $curlResult.HttpStatus = $Matches[1].Trim()
        } elseif ($lines.Count -eq 0) {
            $curlResult.HttpStatus = "ERROR (no output)"
        }
    } catch {
        $curlResult.ErrorMsg  = $_.Exception.Message
        $curlResult.HttpStatus = "ERROR"
    }

    return $curlResult
}

# ── Dispatch all jobs ─────────────────────────────────────────────────────────
# Two runspaces per target — one for DNS, one for curl — both start at the same
# time so DNS and curl run in parallel with each other across all targets.
# DNS runspace receives the extracted Hostname; curl runspace gets the original
# URL (full URL needed for curl so it hits the right path/scheme).
$jobs = foreach ($target in $targets) {
    # DNS job — uses extracted hostname
    $rsDns = [PowerShell]::Create()
    $rsDns.RunspacePool = $pool
    [void]$rsDns.AddScript($scriptBlock).AddArgument($target.Hostname).AddArgument($DnsServer)

    # Curl job — uses original URL; falls back to https://hostname if no scheme given
    $curlUrl = if ($target.Original -match '^\w+://') { $target.Original } else { "https://$($target.Original)" }
    $rsCurl = [PowerShell]::Create()
    $rsCurl.RunspacePool = $pool
    [void]$rsCurl.AddScript($curlScriptBlock).AddArgument($curlUrl)

    [PSCustomObject]@{
        DnsPS    = $rsDns
        DnsH     = $rsDns.BeginInvoke()
        CurlPS   = $rsCurl
        CurlH    = $rsCurl.BeginInvoke()
        Original = $target.Original
        CurlUrl  = $curlUrl
    }
}

# ── Collect results ───────────────────────────────────────────────────────────
# EndInvoke() blocks until each runspace finishes. DNS and curl ran in parallel
# so by the time we reach the slower of the two, the faster is already done.
$allResults = foreach ($job in $jobs) {
    $dns  = $job.DnsPS.EndInvoke($job.DnsH);   $job.DnsPS.Dispose()
    $curl = $job.CurlPS.EndInvoke($job.CurlH); $job.CurlPS.Dispose()
    # Attach original URL and curl result to the DNS result object for output
    $dns | Add-Member -NotePropertyName Original   -NotePropertyValue $job.Original -PassThru |
           Add-Member -NotePropertyName CurlUrl    -NotePropertyValue $job.CurlUrl  -PassThru |
           Add-Member -NotePropertyName CurlResult -NotePropertyValue $curl         -PassThru
}
$pool.Close()
$pool.Dispose()

# ── Per-target detail output ──────────────────────────────────────────────────
$recordTypes = @("A","AAAA","CNAME","MX","TXT","PTR")

foreach ($r in $allResults) {
    # Header — show original URL and extracted hostname if they differ
    $hostLabel = if ($r.Original -ne $r.Hostname) { "$($r.Original)  →  $($r.Hostname)" } else { $r.Hostname }
    Write-Host "`n$("═" * 70)" -ForegroundColor DarkGray
    Write-Host "  $hostLabel" -ForegroundColor Cyan
    Write-Host "$("═" * 70)" -ForegroundColor DarkGray

    # ── DNS section ───────────────────────────────────────────────────────────
    Write-Host "  [DNS]  server: $($r.DnsServer)" -ForegroundColor Yellow
    foreach ($type in $recordTypes) {
        $rec = $r.$type

        $statusColor = switch ($rec.Status) {
            "PASS"  { "Green"    }
            "NONE"  { "DarkGray" }
            "SKIP"  { "DarkGray" }
            default { "Red"      }
        }

        if ($rec.Values.Count -gt 0) {
            $firstVal = $rec.Values[0]
            if ($firstVal.Length -gt 55) { $firstVal = $firstVal.Substring(0,52) + "..." }
            $valStr = $firstVal
        } else {
            $valStr = "(none)"
        }

        Write-Host ("    {0,-5}: {1,-55}" -f $type, $valStr) -NoNewline
        Write-Host "[$($rec.Status)]" -ForegroundColor $statusColor

        # Additional values (multiple A records, multiple MX entries, etc.)
        if ($rec.Values.Count -gt 1) {
            foreach ($extra in $rec.Values[1..($rec.Values.Count - 1)]) {
                if ($extra.Length -gt 55) { $extra = $extra.Substring(0,52) + "..." }
                Write-Host ("           {0}" -f $extra)
            }
        }
    }

    # ── Curl verbose section ──────────────────────────────────────────────────
    $cr = $r.CurlResult
    Write-Host ""
    Write-Host "  [CURL]  $($r.CurlUrl)" -ForegroundColor Yellow

    if ($cr.ErrorMsg) {
        # curl.exe missing or threw an exception
        Write-Host "    ERROR: $($cr.ErrorMsg)" -ForegroundColor Red
    } elseif ($cr.VerboseLines.Count -eq 0) {
        Write-Host "    (no output)" -ForegroundColor DarkGray
    } else {
        foreach ($vl in $cr.VerboseLines) {
            # curl verbose line prefixes:
            #   *  = informational (connection, TLS, server cert details)
            #   >  = request header sent to server
            #   <  = response header received from server
            #   (none / spaces) = data / progress (rare with -s -o NUL)
            $lineColor = switch -Regex ($vl) {
                '^[*]'  { "DarkGray"   }   # connection / TLS info
                '^[>]'  { "DarkCyan"   }   # request headers
                '^[<]'  { "Green"      }   # response headers
                default { "Gray"       }
            }
            Write-Host "    $vl" -ForegroundColor $lineColor
        }
    }
}

# ── Summary table ─────────────────────────────────────────────────────────────
# Columns: original URL | DNS A status | HTTP status from curl
Write-Host "`n$("─" * 70)" -ForegroundColor DarkGray
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host ("  {0,-40} {1,-6} {2,-6} {3,-6} {4,-6} {5,-6} {6,-8} {7}" -f "Target","A","AAAA","CNAME","MX","TXT","PTR","HTTP")
Write-Host ("  {0,-40} {1,-6} {2,-6} {3,-6} {4,-6} {5,-6} {6,-8} {7}" -f ("─"*39),("─"*5),("─"*5),("─"*5),("─"*5),("─"*5),("─"*7),("─"*10))

$resolvedCount = 0; $failedCount = 0
foreach ($r in $allResults) {
    $dnsCols = $recordTypes | ForEach-Object { $r.$_.Status.PadRight(6) }
    $httpStr = if ($r.CurlResult.ErrorMsg)    { "ERROR" }
               elseif ($r.CurlResult.HttpStatus) { $r.CurlResult.HttpStatus }
               else                           { "?" }
    # Truncate long original URLs to fit the column
    $label = $r.Original
    if ($label.Length -gt 39) { $label = $label.Substring(0,36) + "..." }
    $line = "  {0,-40} {1} {2}" -f $label, ($dnsCols -join " "), $httpStr
    if ($r.A.Status -eq "PASS") { $resolvedCount++; $color = "White" } else { $failedCount++; $color = "Red" }
    Write-Host $line -ForegroundColor $color
}

Write-Host "`n  Resolved: $resolvedCount  |  Failed: $failedCount  |  Total: $($allResults.Count)" -ForegroundColor Cyan
Write-Host ("─" * 70) -ForegroundColor DarkGray

Write-Host "`nAll lookups complete. Press any key to exit..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
