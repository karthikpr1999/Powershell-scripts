function New-RandomPassword {
    param(
        [int]$Length = 12
    )

    # Define the character set to use for the password
    # This includes uppercase, lowercase, numbers, and common symbols.
    # You can customize this character set as needed.
    $charSet = "abcdefghijklmnopqrstuvwxyz" +
               "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
               "0123456789" +
               "!@#$%^&*()_-+=[]{}\|;:,.<>/?`~"

    # Use a cryptographically strong random number generator
    # This is more secure than Get-Random for password generation.
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $bytes = [byte[]]::new($Length)
    $rng.GetBytes($bytes)

    $passwordChars = [char[]]::new($Length)
    for ($i = 0; $i -lt $Length; $i++) {
        # Get a random index within the charSet length
        # Using the byte to generate a more "random" index within the range
        $randomIndex = $bytes[$i] % $charSet.Length
        $passwordChars[$i] = $charSet[$randomIndex]
    }

    $password = -join $passwordChars

    # Copy the generated password to the clipboard
    $password | Set-Clipboard

    Write-Host "New password copied to the system clipboard: $password"
    # For security, you might want to remove the echo of the password to console
    # if you're not in a secure environment.
}

# How to use it:
 New-RandomPassword           # Generates a 12-character password
# New-RandomPassword -Length 20 # Generates a 20-character password