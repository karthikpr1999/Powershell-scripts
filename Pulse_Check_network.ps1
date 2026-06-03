# Prompt user for MTU size
do {
    $mtuInput = Read-Host "Enter MTU size to test (default: 1460)"
    if ([string]::IsNullOrWhiteSpace($mtuInput)) { $mtuInput = "1460" }
} while ($mtuInput -notmatch '^\d+$' -or [int]$mtuInput -lt 68 -or [int]$mtuInput -gt 9000)
$MTU = [int]$mtuInput

# Define your list of URLs/IPs here
$Targets = @("google.com", "cloudflare.com", "microsoft.com", "amazon.in","youtube.com","facebook.com","twitter.com","linkedin.com","github.com","netflix.com","mausam.imd.gov.in", "us-east-1.console.aws.amazon.com")

foreach ($Server in $Targets) {
    Write-Host "`n--- Testing Connectivity for: $Server ---" -ForegroundColor Yellow
    
    # 1. IPv4 Check & Display Address
    try {
        $v4Result = Test-Connection $Server -Count 1 -IPv4 -ErrorAction Stop
        Write-Host "IPv4: $($v4Result.IPV4Address) " -NoNewline
        Write-Host "[PASS]" -ForegroundColor Green
    } catch {
        Write-Host "IPv4: (No Resolution/Failed) " -NoNewline
        Write-Host "[FAIL]" -ForegroundColor Red
    }

    # 2. IPv6 Check & Display Address
    try {
        $v6Result = Test-Connection $Server -Count 1 -IPv6 -ErrorAction Stop
        Write-Host "IPv6: $($v6Result.IPV6Address) " -NoNewline
        Write-Host "[PASS]" -ForegroundColor Green
    } catch {
        # Note: Many Indian ISPs or local routers may not fully support IPv6 yet
        Write-Host "IPv6: (None/Disabled) " -NoNewline
        Write-Host "[FAIL/SKIP]" -ForegroundColor Gray
    }

    # 3. MTU Check
    Write-Host "MTU Test ($MTU): " -NoNewline
    $null = ping -n 1 -f -l "$MTU" "$Server"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "[FRAGMENTATION REQUIRED]" -ForegroundColor Magenta
    }
}

Write-Host "`nAll tests complete. Press any key to exit..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null