#Requires -Version 5.1
<#
.SYNOPSIS
    Real-time network throughput monitor — Ethernet & Wi-Fi only.

.DESCRIPTION
    Polls Get-NetAdapterStatistics every second, computes byte-delta → Mbps,
    and renders a clean in-place terminal dashboard.

    Automatically excluded:
      • Virtual switches  (vEthernet, Hyper-V, VMware, VirtualBox)
      • VPN tunnels       (GlobalProtect, AnyConnect, NordVPN, FortiClient …)
      • Loopback / Teredo / ISATAP pseudo-interfaces
      • Bluetooth adapters

    No elevation required — statistics are readable as a standard user.
    Press Ctrl+C to exit cleanly.

.NOTES
    Tested on Windows 10 / 11 with PowerShell 5.1 and PowerShell 7+.
    Best rendered in Windows Terminal or any ANSI-capable console.
#>

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

[int]    $REFRESH_SEC    = 1          # Dashboard refresh cadence (seconds)
[int]    $BITS_PER_BYTE  = 8          # Conversion factor
[int]    $MBPS_DIVISOR   = 1_000_000  # SI Mbps  (NOT 1MB = 1,048,576)

# Case-insensitive substring patterns to exclude from monitoring
[string[]] $EXCLUDE_PATTERNS = @(
    # ── Virtual / Hypervisor ──────────────────────────────────────────────
    'vEthernet', 'Hyper-V', 'Virtual', 'VirtualBox', 'VMware', 'VNet',
    # ── Loopback / Tunnel pseudo-interfaces ──────────────────────────────
    'Loopback', 'Pseudo', 'Teredo', 'ISATAP', '6to4',
    # ── VPN clients ──────────────────────────────────────────────────────
    'VPN', 'Tunnel', 'TAP-', 'TAP Windows', 'Hamachi',
    'NordVPN', 'OpenVPN', 'ExpressVPN', 'Surfshark',
    'GlobalProtect', 'AnyConnect', 'Cisco', 'FortiClient', 'SonicWall',
    'WireGuard', 'ZScaler', 'PulseSecure',
    # ── Bluetooth / legacy ───────────────────────────────────────────────
    'Bluetooth', 'WAN Miniport', 'Miniport', 'RAS'
)

# ─────────────────────────────────────────────────────────────────────────────
#  ANSI COLOR PALETTE  (auto-degrades if console does not support ANSI)
# ─────────────────────────────────────────────────────────────────────────────

$ESC      = [char]27
$RESET    = "$ESC[0m"
$BOLD     = "$ESC[1m"
$DIM      = "$ESC[2m"
$CYAN     = "$ESC[36m"
$BCYAN    = "$ESC[96m"
$GREEN    = "$ESC[32m"
$BGREEN   = "$ESC[92m"
$YELLOW   = "$ESC[33m"
$BYELLOW  = "$ESC[93m"
$RED      = "$ESC[31m"
$BRED     = "$ESC[91m"
$WHITE    = "$ESC[97m"
$BLUE     = "$ESC[34m"
$BBLUE    = "$ESC[94m"
$MAGENTA  = "$ESC[35m"
$BMAGENTA = "$ESC[95m"
$GRAY     = "$ESC[90m"

# ─────────────────────────────────────────────────────────────────────────────
#  HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Test-IsExcluded {
    <# Returns $true if the adapter name or description matches any exclusion pattern. #>
    param([string]$Name, [string]$Description)

    foreach ($pattern in $EXCLUDE_PATTERNS) {
        if ($Name        -like "*$pattern*") { return $true }
        if ($Description -like "*$pattern*") { return $true }
    }
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────

function Get-PhysicalAdapters {
    <#
    Uses the -Physical switch to pre-filter software/virtual adapters at the
    WMI level, then applies our secondary exclusion list for VPN clients and
    other edge-cases that still report as physical.
    #>
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object {
            -not (Test-IsExcluded -Name $_.Name -Description $_.InterfaceDescription)
        }
}

# ─────────────────────────────────────────────────────────────────────────────

function Get-AdapterCategory {
    <# Classify as 'Wi-Fi' or 'Ethernet' based on media type and description. #>
    param([object]$Adapter)

    $iswifi = $Adapter.PhysicalMediaType -eq '802.11'         -or
              $Adapter.MediaType         -in @('Native 802.11','802.11') -or
              $Adapter.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11'

    return $(if ($iswifi) { 'Wi-Fi' } else { 'Ethernet' })
}

# ─────────────────────────────────────────────────────────────────────────────

function Get-ByteSnapshot {
    <#
    Captures ReceivedBytes + SentBytes for each named adapter in one pass.
    Adapters that are down or return no stats are silently skipped.
    Returns a hashtable keyed by adapter name.
    #>
    param([string[]]$Names)

    $snap = @{}
    foreach ($n in $Names) {
        $stat = Get-NetAdapterStatistics -Name $n -ErrorAction SilentlyContinue
        if ($null -ne $stat) {
            $snap[$n] = [PSCustomObject]@{
                RxBytes = [long]$stat.ReceivedBytes
                TxBytes = [long]$stat.SentBytes
                Time    = [datetime]::UtcNow
            }
        }
    }
    return $snap
}

# ─────────────────────────────────────────────────────────────────────────────

function ConvertTo-Mbps {
    <# Delta bytes over elapsed seconds → Megabits per second (SI). #>
    param([long]$DeltaBytes, [double]$ElapsedSec)

    if ($DeltaBytes -lt 0)     { $DeltaBytes = 0 }
    if ($ElapsedSec -le 0)     { return 0.0 }

    return ($DeltaBytes * $BITS_PER_BYTE) / $ElapsedSec / $MBPS_DIVISOR
}

# ─────────────────────────────────────────────────────────────────────────────

function Format-MbpsValue {
    <# Right-aligned, 3-decimal string, 9 chars wide. #>
    param([double]$Mbps)
    $safe = if ([double]::IsNaN($Mbps) -or [double]::IsInfinity($Mbps)) { 0.0 } else { $Mbps }
    return ('{0,9:F3}' -f [Math]::Max(0.0, $safe))
}

# ─────────────────────────────────────────────────────────────────────────────

function Get-SpeedColor {
    <# Color-grades Mbps: idle=dim, low=green, medium=yellow, high=red. #>
    param([double]$Mbps)

    if ([double]::IsNaN($Mbps) -or [double]::IsInfinity($Mbps)) { return $DIM }
    if ($Mbps -ge 500)  { return $BRED    }
    if ($Mbps -ge 100)  { return $RED     }
    if ($Mbps -ge 25)   { return $BYELLOW }
    if ($Mbps -ge 1)    { return $BGREEN  }
    if ($Mbps -gt 0)    { return $GREEN   }
    return $DIM
}

# ─────────────────────────────────────────────────────────────────────────────

function Get-StatusDecoration {
    <# Returns colored status icon + label pair. #>
    param([string]$Status)

    switch ($Status) {
        'Up'            { return @{ Color = $BGREEN;  Icon = '●'; Label = 'Up'           } }
        'Disconnected'  { return @{ Color = $BYELLOW; Icon = '○'; Label = 'Disconnected' } }
        'Disabled'      { return @{ Color = $GRAY;    Icon = '✕'; Label = 'Disabled'     } }
        'NotPresent'    { return @{ Color = $RED;     Icon = '!'; Label = 'Not Present'  } }
        default         { return @{ Color = $DIM;     Icon = '?'; Label = $Status        } }
    }
}

# ─────────────────────────────────────────────────────────────────────────────

function Remove-AnsiCodes {
    <# Strip ANSI escape sequences to calculate visible string length. #>
    param([string]$Text)
    return ($Text -replace '\x1B\[[0-9;]*[A-Za-z]', '')
}

# ─────────────────────────────────────────────────────────────────────────────

function Write-PaddedLine {
    <#
    Writes a line to the console, padding it to the full terminal width
    so that any previously-rendered content on that row is erased.
    Uses direct Console.Write to avoid appending a newline that causes scroll.
    #>
    param([string]$Line, [int]$Width)

    $visibleLen = (Remove-AnsiCodes $Line).Length
    $padding    = [Math]::Max(0, $Width - 1 - $visibleLen)
    [Console]::Write($Line + (' ' * $padding) + "`n")
}

# ─────────────────────────────────────────────────────────────────────────────
#  DASHBOARD RENDERER
# ─────────────────────────────────────────────────────────────────────────────

function Build-Dashboard {
    <#
    Constructs the full dashboard as an array of ANSI-colored strings.
    No console I/O happens here — pure string building.
    #>
    param(
        [object[]]  $Adapters,
        [hashtable] $CurrSnap,
        [hashtable] $PrevSnap,
        [double]    $ElapsedSec
    )

    # ── Layout metrics ────────────────────────────────────────────────────────
    $W         = [Math]::Min([Console]::WindowWidth, 110)
    $lineDouble = '═' * $W
    $lineSingle = '─' * $W

    # ── Column widths ─────────────────────────────────────────────────────────
    $COL_NAME   = 30   # Adapter name (truncated if longer)
    $COL_TYPE   = 10   # Ethernet / Wi-Fi
    $COL_STATUS = 14   # Status label
    $COL_SPEED  =  9   # Mbps value (right-aligned)

    $output = [System.Collections.Generic.List[string]]::new()

    # ─── Title bar ────────────────────────────────────────────────────────────
    $ts    = Get-Date -Format 'ddd, dd-MMM-yyyy  HH:mm:ss'
    $title = "  NetSpeedMonitor  |  $ts  |  Refresh: ${REFRESH_SEC}s"

    $output.Add("${BOLD}${BCYAN}${lineDouble}${RESET}")
    $output.Add("${BOLD}${WHITE}${title}${RESET}")
    $output.Add("${BOLD}${BCYAN}${lineDouble}${RESET}")

    # ─── Column headers ───────────────────────────────────────────────────────
    $hdrFmt = "  {0,-$COL_NAME} {1,-$COL_TYPE} {2,-$COL_STATUS} {3,$COL_SPEED}   {4,$COL_SPEED}"
    $header  = $hdrFmt -f 'Adapter Name', 'Type', 'Status', 'RX Mbps', 'TX Mbps'

    $output.Add("${BOLD}${BBLUE}${header}${RESET}")
    $output.Add("${DIM}${lineSingle}${RESET}")

    # ─── Per-adapter rows ─────────────────────────────────────────────────────
    $totals = @{
        Ethernet = @{ Rx = 0.0; Tx = 0.0 }
        'Wi-Fi'  = @{ Rx = 0.0; Tx = 0.0 }
    }

    # Sort: Ethernet first, then Wi-Fi; alphabetically within each group
    $sorted = $Adapters | Sort-Object { Get-AdapterCategory $_ }, Name

    foreach ($adapter in $sorted) {
        $name     = $adapter.Name
        $category = Get-AdapterCategory -Adapter $adapter
        $status   = if ($null -ne $adapter.Status) { $adapter.Status.ToString() } else { 'Unknown' }
        $deco     = Get-StatusDecoration -Status $status

        # ── Compute Mbps (only when Up and both snapshots present) ────────────
        $rxMbps = 0.0
        $txMbps = 0.0

        if ($status -eq 'Up' -and
            $CurrSnap.ContainsKey($name) -and
            $PrevSnap.ContainsKey($name)) {

            $rxDelta = $CurrSnap[$name].RxBytes - $PrevSnap[$name].RxBytes
            $txDelta = $CurrSnap[$name].TxBytes - $PrevSnap[$name].TxBytes

            $rxMbps  = ConvertTo-Mbps -DeltaBytes $rxDelta -ElapsedSec $ElapsedSec
            $txMbps  = ConvertTo-Mbps -DeltaBytes $txDelta -ElapsedSec $ElapsedSec

            $totals[$category].Rx += $rxMbps
            $totals[$category].Tx += $txMbps
        }

        # ── Render values (dash when not Up) ─────────────────────────────────
        $rxStr   = if ($status -eq 'Up') { Format-MbpsValue $rxMbps } else { '      ---' }
        $txStr   = if ($status -eq 'Up') { Format-MbpsValue $txMbps } else { '      ---' }
        $rxColor = if ($status -eq 'Up') { Get-SpeedColor   $rxMbps } else { $GRAY }
        $txColor = if ($status -eq 'Up') { Get-SpeedColor   $txMbps } else { $GRAY }

        # ── Type color ────────────────────────────────────────────────────────
        $typeColor = if ($category -eq 'Wi-Fi') { $BMAGENTA } else { $BCYAN }

        # ── Truncate long adapter names gracefully ────────────────────────────
        $displayName = if ($name.Length -gt ($COL_NAME - 1)) {
            $name.Substring(0, $COL_NAME - 4) + '...'
        } else { $name }

        # ── Status badge with icon ────────────────────────────────────────────
        $statusBadge = "$($deco.Icon) $($deco.Label)".PadRight($COL_STATUS)

        # ── Assemble row (ANSI codes do not count toward column widths) ───────
        $row = ("  ${WHITE}{0,-$COL_NAME}${RESET} " +
                "${typeColor}{1,-$COL_TYPE}${RESET} " +
                "$($deco.Color){2,-$COL_STATUS}${RESET} " +
                "${rxColor}{3,$COL_SPEED}${RESET}   " +
                "${txColor}{4,$COL_SPEED}${RESET}") `
            -f $displayName, $category, $statusBadge, $rxStr, $txStr

        $output.Add($row)
    }

    # ─── Totals section ───────────────────────────────────────────────────────
    $output.Add("${DIM}${lineSingle}${RESET}")

    foreach ($cat in @('Ethernet', 'Wi-Fi')) {
        $rx       = $totals[$cat].Rx
        $tx       = $totals[$cat].Tx
        $tColor   = if ($cat -eq 'Wi-Fi') { $BMAGENTA } else { $BCYAN }
        $rxColor  = Get-SpeedColor $rx
        $txColor  = Get-SpeedColor $tx
        $label    = "$cat TOTAL"

        $totalRow = ("  ${BOLD}${WHITE}{0,-$COL_NAME}${RESET} " +
                     "${tColor}{1,-$COL_TYPE}${RESET} " +
                     "{2,-$COL_STATUS} " +
                     "${rxColor}{3,$COL_SPEED}${RESET}   " +
                     "${txColor}{4,$COL_SPEED}${RESET}") `
            -f $label, $cat, '', (Format-MbpsValue $rx), (Format-MbpsValue $tx)

        $output.Add($totalRow)
    }

    # ─── Footer ───────────────────────────────────────────────────────────────
    $output.Add("${BOLD}${BCYAN}${lineDouble}${RESET}")
    $output.Add("  ${DIM}Ctrl+C to exit  |  Excludes: virtual, VPN, loopback, Bluetooth${RESET}")
    $output.Add('')   # trailing blank keeps cursor off the last content line

    return $output
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN MONITORING LOOP
# ─────────────────────────────────────────────────────────────────────────────

# Console setup
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::CursorVisible  = $false
Clear-Host

$prevSnap       = @{}
$prevTime       = [datetime]::UtcNow
$prevLineCount  = 0
$firstRender    = $true

try {
    while ($true) {

        # ── Discover adapters fresh each cycle (handles hot-plug / disable) ──
        $adapters = @(Get-PhysicalAdapters)

        # ── Guard: no adapters detected ──────────────────────────────────────
        if ($adapters.Count -eq 0) {
            if ($firstRender) {
                Clear-Host
                $firstRender = $false
            }
            [Console]::SetCursorPosition(0, 0)
            $msg = "  ${BYELLOW}No physical adapters detected — retrying in ${REFRESH_SEC}s...${RESET}"
            Write-PaddedLine -Line $msg -Width ([Console]::WindowWidth)
            Start-Sleep -Seconds $REFRESH_SEC
            continue
        }

        # ── Capture current statistics snapshot ───────────────────────────────
        $names    = $adapters | Select-Object -ExpandProperty Name
        $currSnap = Get-ByteSnapshot -Names $names

        # ── Calculate elapsed time (guards against sub-millisecond deltas) ───
        $now      = [datetime]::UtcNow
        $elapsed  = ($now - $prevTime).TotalSeconds
        if ($elapsed -lt 0.1) { $elapsed = $REFRESH_SEC }

        # ── Build dashboard lines ─────────────────────────────────────────────
        $lines     = Build-Dashboard -Adapters    $adapters  `
                                     -CurrSnap    $currSnap  `
                                     -PrevSnap    $prevSnap  `
                                     -ElapsedSec  $elapsed

        $lineCount = $lines.Count
        $termWidth = [Console]::WindowWidth

        # ── On first render, clear the screen cleanly ─────────────────────────
        if ($firstRender) {
            Clear-Host
            $firstRender = $false
        }

        # ── Render in-place (cursor jumps to row 0, no scroll) ───────────────
        [Console]::SetCursorPosition(0, 0)

        foreach ($line in $lines) {
            Write-PaddedLine -Line $line -Width $termWidth
        }

        # ── Erase ghost rows if dashboard shrank (e.g. adapter removed) ──────
        if ($lineCount -lt $prevLineCount) {
            $blank = ' ' * ($termWidth - 1)
            for ($i = $lineCount; $i -lt $prevLineCount; $i++) {
                [Console]::WriteLine($blank)
            }
        }

        # ── Roll state forward ────────────────────────────────────────────────
        $prevSnap      = $currSnap
        $prevTime      = $now
        $prevLineCount = $lineCount

        Start-Sleep -Seconds $REFRESH_SEC
    }
}
finally {
    # ── Restore terminal on Ctrl+C or any exit ────────────────────────────────
    [Console]::CursorVisible = $true
    [Console]::SetCursorPosition(0, $prevLineCount + 1)
    Write-Host "`n  ${BCYAN}NetSpeedMonitor stopped.${RESET}`n"
}