# ==========================================
# QUICK VPN CONNECTIVITY VALIDATION
# ==========================================

# -------- CONFIGURATION --------
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   VPN CONNECTIVITY VALIDATION SETUP"     -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

function Read-Input {
    param([string]$Prompt, [string]$Default)
    $display = if ($Default) { "$Prompt [default: $Default]" } else { $Prompt }
    $value   = (Read-Host $display).Trim()
    if ([string]::IsNullOrEmpty($value)) { $Default } else { $value }
}

$ExternalHost    = Read-Input "External hostname or IP  (e.g. google.com)"      "google.com"
$InternalHost    = Read-Input "Internal hostname or IP  (e.g. cam.int.sap)"     "cam.int.sap"
$ExternalWebSite = Read-Input "External website URL     (e.g. https://...)"     "https://www.google.com"
$InternalWebSite = Read-Input "Internal website URL     (e.g. https://...)"     "https://wiki.one.int.sap"

# Ensure website values start with https:// if the user omitted the scheme
foreach ($var in @('ExternalWebSite','InternalWebSite')) {
    $val = (Get-Variable $var).Value
    if ($val -and $val -notmatch '^https?://') {
        Set-Variable $var "https://$val"
    }
}

Write-Host ""

$Results   = [System.Collections.Generic.List[PSCustomObject]]::new()
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Add-Result {
    param([string]$Test, [bool]$Passed, [string]$Detail = "")
    $Results.Add([PSCustomObject]@{
        Test   = $Test
        Status = if ($Passed) { "PASS" } else { "FAIL" }
        Detail = $Detail
    })
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   VPN CONNECTIVITY VALIDATION STARTED"   -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  External Host : $ExternalHost"
Write-Host "  Internal Host : $InternalHost"
Write-Host "  External Site : $ExternalWebSite"
Write-Host "  Internal Site : $InternalWebSite"
Write-Host ""

# ==========================================
# ADMIN CHECK
# ==========================================
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "[WARNING] Not running as Administrator. Some results may be incomplete." -ForegroundColor Yellow
    Write-Host ""
}

# ==========================================
# VPN ADAPTER INFORMATION (fast local call — run before parallel block)
# ==========================================
Write-Host "========== VPN ADAPTER DETAILS ==========" -ForegroundColor Cyan
$VpnAdapters = Get-NetIPConfiguration | Where-Object {
    $_.InterfaceDescription -match "PANGP|GlobalProtect|VPN"
}
if ($VpnAdapters) {
    $VpnAdapters | ForEach-Object {
        $dns = ($_.DNSServer | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ }) -join ', '
        [PSCustomObject]@{
            InterfaceAlias = $_.InterfaceAlias
            IPv4Address    = ($_.IPv4Address.IPAddress -join ', ')
            DNSServers     = $dns
        }
    } | Format-Table -AutoSize
    Add-Result "VPN Adapter Detected" $true ($VpnAdapters.InterfaceAlias -join ", ")
} else {
    Write-Host "No VPN adapter found." -ForegroundColor Yellow
    Add-Result "VPN Adapter Detected" $false "No matching adapter"
}
Write-Host ""

# ==========================================
# FULL IP CONFIGURATION
# ==========================================
Write-Host "========== FULL IP CONFIGURATION ==========" -ForegroundColor Cyan
ipconfig /all
Write-Host ""

# ==========================================
# PARALLEL NETWORK TESTS
# All 8 tests (DNS x2, Ping x2, TCP x2, HTTPS x2) run simultaneously
# via a runspace pool — total wall time = slowest single test, not their sum
# ==========================================
Write-Host "========== RUNNING NETWORK TESTS IN PARALLEL ==========" -ForegroundColor Cyan
Write-Host "  DNS, Ping, TCP, and HTTPS running simultaneously..." -ForegroundColor Gray
Write-Host ""

# Each scriptblock returns [PSCustomObject]@{ Passed; Detail; Display }
# Display is pre-formatted as a string to avoid cross-runspace serialization issues

$SB_DNS = {
    param($HostName)
    $r = Resolve-DnsName $HostName -ErrorAction SilentlyContinue
    if ($r) {
        $display = ($r | Select-Object -First 3 | Format-Table Name, Type, IPAddress -AutoSize | Out-String).Trim()
        [PSCustomObject]@{ Passed = $true;  Detail = $r[0].IPAddress; Display = $display }
    } else {
        [PSCustomObject]@{ Passed = $false; Detail = "No response";   Display = "  FAILED" }
    }
}

$SB_Ping = {
    param($HostName)
    $r = Test-Connection -ComputerName $HostName -Count 4 -ErrorAction SilentlyContinue
    if ($r) {
        $avg     = ($r | Measure-Object -Property Latency -Average).Average
        $display = ($r | Format-Table Address, Latency -AutoSize | Out-String).Trim()
        [PSCustomObject]@{ Passed = $true;  Detail = "Avg $([math]::Round($avg,0))ms"; Display = $display }
    } else {
        [PSCustomObject]@{ Passed = $false; Detail = "No response"; Display = "  FAILED" }
    }
}

# TcpClient is used instead of Test-NetConnection — no ping overhead, 3s timeout
$SB_TCP = {
    param($HostName, $Port)
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $ar  = $tcp.BeginConnect($HostName, $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne(3000)
        if ($ok -and $tcp.Connected) {
            $tcp.Close()
            [PSCustomObject]@{ Passed = $true;  Detail = "Port $Port open" }
        } else {
            $tcp.Close()
            [PSCustomObject]@{ Passed = $false; Detail = "Port $Port blocked or timeout" }
        }
    } catch {
        [PSCustomObject]@{ Passed = $false; Detail = $_.Exception.Message }
    }
}

$SB_HTTPS = {
    param($Uri)
    try {
        $r = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        [PSCustomObject]@{ Passed = $true;  Detail = "HTTP $($r.StatusCode)" }
    } catch {
        [PSCustomObject]@{ Passed = $false; Detail = $_.Exception.Message }
    }
}

$Pool = [RunspaceFactory]::CreateRunspacePool(1, 8)
$Pool.Open()

$JobDefs = @(
    [PSCustomObject]@{ Key = "DNS_Ext";   SB = $SB_DNS;   Args = @($ExternalHost)          }
    [PSCustomObject]@{ Key = "DNS_Int";   SB = $SB_DNS;   Args = @($InternalHost)           }
    [PSCustomObject]@{ Key = "Ping_Ext";  SB = $SB_Ping;  Args = @($ExternalHost)           }
    [PSCustomObject]@{ Key = "Ping_Int";  SB = $SB_Ping;  Args = @($InternalHost)           }
    [PSCustomObject]@{ Key = "TCP_Ext";   SB = $SB_TCP;   Args = @($ExternalHost, 443)      }
    [PSCustomObject]@{ Key = "TCP_Int";   SB = $SB_TCP;   Args = @($InternalHost, 443) }
    [PSCustomObject]@{ Key = "HTTPS_Ext"; SB = $SB_HTTPS; Args = @($ExternalWebSite)        }
    [PSCustomObject]@{ Key = "HTTPS_Int"; SB = $SB_HTTPS; Args = @($InternalWebSite)        }
)

# Launch all runspaces simultaneously
$ActiveJobs = foreach ($Def in $JobDefs) {
    $PS = [PowerShell]::Create()
    $PS.RunspacePool = $Pool
    $null = $PS.AddScript($Def.SB)
    $Def.Args | ForEach-Object { $null = $PS.AddArgument($_) }
    [PSCustomObject]@{ Key = $Def.Key; PS = $PS; Handle = $PS.BeginInvoke() }
}

# Collect results — wrap in try/catch so a runspace error gives a usable fallback
$R = @{}
foreach ($J in $ActiveJobs) {
    try {
        $out       = $J.PS.EndInvoke($J.Handle)
        $R[$J.Key] = if ($out.Count -gt 0) { $out[0] } else {
            [PSCustomObject]@{ Passed = $false; Detail = "No output from runspace"; Display = "  NO OUTPUT" }
        }
    } catch {
        $msg       = $_.Exception.InnerException.Message ?? $_.Exception.Message
        $R[$J.Key] = [PSCustomObject]@{ Passed = $false; Detail = $msg; Display = "  ERROR: $msg" }
    }
    $J.PS.Dispose()
}
$Pool.Close()
$Pool.Dispose()

# ---- Display: DNS ----
Write-Host "========== DNS TESTS ==========" -ForegroundColor Cyan
Write-Host ""
Write-Host "External DNS ($ExternalHost):"
Write-Host $R["DNS_Ext"].Display
Add-Result "DNS External ($ExternalHost)" ([bool]$R["DNS_Ext"].Passed) $R["DNS_Ext"].Detail

Write-Host ""
Write-Host "Internal DNS ($InternalHost):"
Write-Host $R["DNS_Int"].Display
Add-Result "DNS Internal ($InternalHost)" ([bool]$R["DNS_Int"].Passed) $R["DNS_Int"].Detail
Write-Host ""

# ---- Display: Ping ----
Write-Host "========== PING TESTS ==========" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ping External ($ExternalHost):"
Write-Host $R["Ping_Ext"].Display
Add-Result "Ping External ($ExternalHost)" ([bool]$R["Ping_Ext"].Passed) $R["Ping_Ext"].Detail

Write-Host ""
Write-Host "Ping Internal ($InternalHost):"
Write-Host $R["Ping_Int"].Display
Add-Result "Ping Internal ($InternalHost)" ([bool]$R["Ping_Int"].Passed) $R["Ping_Int"].Detail
Write-Host ""

# ---- Display: TCP ----
Write-Host "========== TCP PORT 443 TESTS ==========" -ForegroundColor Cyan
Write-Host ""
foreach ($Entry in @(
    [PSCustomObject]@{ Key = "TCP_Ext"; Host = $ExternalHost        }
    [PSCustomObject]@{ Key = "TCP_Int"; Host = $InternalHost   }
)) {
    $Res   = $R[$Entry.Key]
    $Color = if ($Res.Passed) { "Green" } else { "Red" }
    $State = if ($Res.Passed) { "OPEN"  } else { "BLOCKED/UNREACHABLE" }
    Write-Host "TCP 443 -> $($Entry.Host) :  $State  ($($Res.Detail))" -ForegroundColor $Color
    Add-Result "TCP 443 ($($Entry.Host))" ([bool]$Res.Passed) $Res.Detail
}
Write-Host ""

# ---- Display: HTTPS ----
Write-Host "========== HTTPS TESTS ==========" -ForegroundColor Cyan
foreach ($Entry in @(
    [PSCustomObject]@{ Key = "HTTPS_Ext"; Site = $ExternalWebSite }
    [PSCustomObject]@{ Key = "HTTPS_Int"; Site = $InternalWebSite }
)) {
    $Res   = $R[$Entry.Key]
    $Color = if ($Res.Passed) { "Green" } else { "Red" }
    $Icon  = if ($Res.Passed) { "SUCCESS" } else { "FAILED" }
    Write-Host ""
    Write-Host "Testing: $($Entry.Site)"
    Write-Host "  $Icon  ($($Res.Detail))" -ForegroundColor $Color
    Add-Result "HTTPS $($Entry.Site)" ([bool]$Res.Passed) $Res.Detail
}
Write-Host ""

# ==========================================
# PARALLEL TRACEROUTE
# Both jobs start at the same time; we display them sequentially after
# ==========================================
Write-Host "========== TRACEROUTE TESTS ==========" -ForegroundColor Cyan
Write-Host "  Both traceroutes running in parallel..." -ForegroundColor Gray
Write-Host ""

$TraceExt = Start-Job { param($h) tracert -d -w 1000 $h } -ArgumentList $ExternalHost
$TraceInt = Start-Job { param($h) tracert -d -w 1000 $h } -ArgumentList $InternalHost

Write-Host "Traceroute -> $ExternalHost :"
Receive-Job $TraceExt -Wait | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Traceroute -> $InternalHost :"
Receive-Job $TraceInt -Wait | ForEach-Object { Write-Host $_ }
Remove-Job $TraceExt, $TraceInt
Write-Host ""

# ==========================================
# ROUTING TABLE
# ==========================================
Write-Host "========== ROUTING TABLE ==========" -ForegroundColor Cyan
route print
Write-Host ""

# ==========================================
# SUMMARY
# ==========================================
$Stopwatch.Stop()

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   RESULTS SUMMARY"                        -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($Item in $Results) {
    $Color = if ($Item.Status -eq "PASS") { "Green" } else { "Red" }
    $Line  = "  [{0}]  {1}" -f $Item.Status, $Item.Test
    if ($Item.Detail) { $Line += "  —  $($Item.Detail)" }
    Write-Host $Line -ForegroundColor $Color
}

$PassCount = ($Results | Where-Object Status -eq "PASS").Count
$FailCount = ($Results | Where-Object Status -eq "FAIL").Count

Write-Host ""
Write-Host ("  Total: {0} checks  |  {1} passed  |  {2} failed  |  Completed in {3:N1}s" -f `
    $Results.Count, $PassCount, $FailCount, $Stopwatch.Elapsed.TotalSeconds) -ForegroundColor Cyan
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   VPN CONNECTIVITY VALIDATION COMPLETED"  -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
