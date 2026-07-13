# Ping-HostnameTest

A PowerShell script that pings multiple hosts **simultaneously** using a RunspacePool, collects latency statistics, prints a colour-coded console summary, and saves results to a timestamped CSV file.

---

## Features

- Pings all hosts **in parallel** — total run time equals one host's time, not all hosts combined
- Collects **min / max / average latency** and **packet loss %** per host
- Colour-coded console output — green for healthy, red for packet loss
- Auto-saves results to a **timestamped CSV** next to the script (no path needed)
- Input validation blocks command injection via hostname parameters
- No external modules — uses only built-in .NET and PowerShell 5.1+

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- No admin rights required (ICMP ping works as a standard user)

---

## Usage

```powershell
# Basic — uses default hosts (google.com, cloudflare.com, 1.1.1.1, 8.8.8.8), 1000 pings each
.\Ping-HostnameTest.ps1

# Custom hosts and ping count
.\Ping-HostnameTest.ps1 -Hostnames "8.8.8.8","10.0.0.1" -PingCount 500

# Add a delay between pings to avoid rate-limiting
.\Ping-HostnameTest.ps1 -Hostnames "8.8.8.8","1.1.1.1" -PingCount 200 -DelayMs 50

# Save CSV to a custom path
.\Ping-HostnameTest.ps1 -OutputCSV "C:\Reports\ping_results.csv"

# Suppress the progress bar (useful in CI or scheduled tasks)
.\Ping-HostnameTest.ps1 -NoProgressBar
```

---

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Hostnames` | `string[]` | `google.com`, `cloudflare.com`, `1.1.1.1`, `8.8.8.8` | One or more hostnames or IPs to ping |
| `-PingCount` | `int` | `1000` | Number of ICMP pings per host |
| `-Timeout` | `int` | `5000` | Per-ping timeout in milliseconds |
| `-DelayMs` | `int` | `0` | Pause between each ping in milliseconds |
| `-OutputCSV` | `string` | `PingResults_yyyyMMdd_HHmmss.csv` | Output file path — auto-generated if omitted |
| `-NoProgressBar` | `switch` | off | Suppresses the progress bar |

---

## Output

### Console

```
========================================
Mass Ping Utility (Parallel)
========================================
Hostnames:   google.com, 1.1.1.1
Pings/Host:  1000
Timeout:     5000ms
Delay:       0ms
Total Pings: 2000
========================================

All 2 hosts pinging simultaneously...

--- Summary for google.com ---
  Sent:        1000
  Received:    1000
  Lost:        0
  Loss %:      0%
  Min/Max/Avg: 11ms / 45ms / 13.2ms
  Success:     100%

--- Summary for 1.1.1.1 ---
  Sent:        1000
  Received:    998
  Lost:        2
  Loss %:      0.2%
  Min/Max/Avg: 8ms / 60ms / 9.1ms
  Success:     99.8%

========================================
OVERALL SUMMARY
========================================
Duration:       12.5s
Hosts Tested:   2
Total Sent:     2000
Total Received: 1998
Overall Loss:   0.1%
========================================
```

### CSV

A file named `PingResults_20260707_163209.csv` is saved in the same folder as the script.

| Hostname | Sent | Received | Lost | LossPercent | MinTime_ms | MaxTime_ms | AvgTime_ms | SuccessRate | UniqueErrors |
|---|---|---|---|---|---|---|---|---|---|
| google.com | 1000 | 1000 | 0 | 0 | 11 | 45 | 13.2 | 100 | 0 |
| 1.1.1.1 | 1000 | 998 | 2 | 0.2 | 8 | 60 | 9.1 | 99.8 | 0 |

---

## How It Works

```
Script starts
     │
     ├─ Validate all hostnames (regex check)
     │
     ├─ Create RunspacePool (1 slot per host)
     │
     ├─ BeginInvoke() — all hosts start pinging at the same time
     │      ├─ host 1: ping loop (1000 × .Send())
     │      ├─ host 2: ping loop (1000 × .Send())
     │      └─ host N: ping loop (1000 × .Send())
     │
     ├─ Poll progress bar until all handles complete
     │
     ├─ EndInvoke() — collect stats from each runspace
     │
     ├─ Print per-host summary to console
     │
     ├─ Print overall summary to console
     │
     └─ Export results to CSV
```

Each runspace:
1. Creates its own `System.Net.NetworkInformation.Ping` socket
2. Sends `$PingCount` ICMP echo requests, recording round-trip time for each success
3. Calculates loss %, success rate, min/max/avg latency
4. Returns a stats object back to the main thread via `EndInvoke`

---

## Files

```
Ping_multihosts/
├── Ping-HostnameTest.ps1        # Main script
└── PingResults_<timestamp>.csv  # Auto-generated on each run (gitignored)
```
