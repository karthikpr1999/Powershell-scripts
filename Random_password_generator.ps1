function New-RandomPassword {
    param(
        [int]$Length       = 12,
        [int]$Count        = 1,
        [switch]$NoSymbols,
        [switch]$NoNumbers,
        [switch]$NoUpper
    )

    # ---- Minimum length guard ----
    if ($Length -lt 8) {
        Write-Host "ERROR: Minimum password length is 8 characters." -ForegroundColor Red
        return
    }

    # ---- Build character classes ----
    $Lower   = "abcdefghijklmnopqrstuvwxyz"
    $Upper   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $Digits  = "0123456789"
    $Symbols = "!@#$%^&*()_-+=[]{}\|;:,.<>/?``~"

    $CharSet  = $Lower
    $Required = @($Lower)   # at least one from each active class

    if (-not $NoUpper)   { $CharSet += $Upper;   $Required += $Upper   }
    if (-not $NoNumbers) { $CharSet += $Digits;  $Required += $Digits  }
    if (-not $NoSymbols) { $CharSet += $Symbols; $Required += $Symbols }

    # ---- Entropy info ----
    $Entropy = [math]::Round([math]::Log($CharSet.Length, 2) * $Length, 1)
    $Strength = switch ($Entropy) {
        { $_ -lt 40 } { "Weak";   break }
        { $_ -lt 60 } { "Fair";   break }
        { $_ -lt 80 } { "Strong"; break }
        default        { "Very Strong" }
    }
    $StrengthColor = switch ($Strength) {
        "Weak"        { "Red"     }
        "Fair"        { "Yellow"  }
        "Strong"      { "Green"   }
        "Very Strong" { "Cyan"    }
    }

    # ---- Bias-free random byte helper ----
    # Discards bytes that fall in the remainder range to eliminate modulo bias
    # Uses an instance (works on .NET Framework / PS 5.1 and .NET 6+ / PS 7)
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    function Get-UnbiasedIndex {
        param([System.Security.Cryptography.RandomNumberGenerator]$Rng, [int]$Max)
        $cutoff = 256 - (256 % $Max)
        $buf    = [byte[]]::new(1)
        do {
            $Rng.GetBytes($buf)
        } while ($buf[0] -ge $cutoff)
        return $buf[0] % $Max
    }

    # ---- Generate passwords ----
    $Passwords = for ($p = 0; $p -lt $Count; $p++) {
        $valid = $false
        while (-not $valid) {
            $chars = [char[]]::new($Length)
            for ($i = 0; $i -lt $Length; $i++) {
                $chars[$i] = $CharSet[(Get-UnbiasedIndex $Rng $CharSet.Length)]
            }

            # Guarantee at least one character from every active class
            $valid = $true
            foreach ($class in $Required) {
                if (-not ($chars | Where-Object { $class.Contains($_) })) {
                    $valid = $false
                    break
                }
            }
        }
        -join $chars
    }

    $Rng.Dispose()

    # ---- Display ----
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "   PASSWORD GENERATOR RESULTS"            -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  Length   : {0} characters"   -f $Length)
    Write-Host ("  Charset  : {0} characters"   -f $CharSet.Length)
    Write-Host ("  Entropy  : {0} bits"         -f $Entropy)
    Write-Host -NoNewline "  Strength : "
    Write-Host $Strength -ForegroundColor $StrengthColor
    Write-Host ""

    if ($Count -eq 1) {
        Write-Host "  Password : " -NoNewline
        Write-Host $Passwords[0] -ForegroundColor Yellow
    } else {
        Write-Host "  Generated $Count passwords:"
        for ($i = 0; $i -lt $Passwords.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $Passwords[$i]) -ForegroundColor Yellow
        }
    }

    Write-Host ""

    Write-Host "=========================================" -ForegroundColor Cyan
}

# ---- Entry point ----
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   RANDOM PASSWORD GENERATOR"             -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Options (press Enter to accept defaults)"
Write-Host ""

$len = (Read-Host "  Password length        [default: 12]").Trim()
$cnt = (Read-Host "  How many passwords     [default:  1]").Trim()
$ns  = (Read-Host "  Exclude symbols? (y/n) [default:  n]").Trim()
$nn  = (Read-Host "  Exclude numbers? (y/n) [default:  n]").Trim()
$nu  = (Read-Host "  Exclude uppercase?(y/n) [default: n]").Trim()

$params = @{}
if ($len -match '^\d+$')    { $params['Length']    = [int]$len }
if ($cnt -match '^\d+$')    { $params['Count']     = [int]$cnt }
if ($ns  -match '^y(es)?$') { $params['NoSymbols'] = $true     }
if ($nn  -match '^y(es)?$') { $params['NoNumbers'] = $true     }
if ($nu  -match '^y(es)?$') { $params['NoUpper']   = $true     }

New-RandomPassword @params
