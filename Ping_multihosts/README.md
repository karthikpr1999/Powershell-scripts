# Ping-HostnameTest

A PowerShell script that pings multiple hosts **simultaneously** using a RunspacePool, shows a **live per-host ping counter** while pinging is in progress, prints each host's summary **as soon as it finishes** (without waiting for the others), and saves all results to a timestamped CSV file.

---

## Features

- Pings all hosts **in parallel** — total run time equals one host's time, not all hosts combined
- **Live progress bar per host** — shows `Ping 650 / 1000` updating in real time while pinging
- **Immediate per-host summary** — printed the moment a host finishes, other hosts keep running
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

# Suppress the progress bars (useful in CI or scheduled tasks)
.\Ping-HostnameTest.ps1 -NoProgressBar
```

---

## Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-Hostnames` | `string[]` | `google.com`, `cloudflare.com`, `1.1.1.1`, `8.8.8.8` | One or more hostnames or IPs to ping |
| `-PingCount` | `int` | `1000` | Number of ICMP pings per host |
| `-Timeout` | `int` | `5000` | Per-ping timeout in milliseconds |
| `-DelayMs` | `int` | `0` | Pause between each ping in milliseconds |
| `-OutputCSV` | `string` | `PingResults_yyyyMMdd_HHmmss.csv` | Output file path — auto-generated if omitted |
| `-NoProgressBar` | `switch` | off | Suppresses all progress bars |

---

## Output

### Console — while pinging

Each host gets its own live progress bar showing the current ping count:

```text
All 4 hosts pinging simultaneously...

  Pinging google.com     [===========>     ] Ping 650 / 1000
  Pinging cloudflare.com [================>] Ping 980 / 1000
  Pinging 1.1.1.1        [======>          ] Ping 400 / 1000
  Pinging 8.8.8.8        [=========>       ] Ping 550 / 1000
```

### Console — as each host finishes

The moment a host completes its pings, its summary is printed immediately — without waiting for the remaining hosts:

```text
--- Summary for cloudflare.com ---       ← printed as soon as it finishes
  Sent:        1000
  Received:    1000
  Lost:        0
  Loss %:      0%
  Min/Max/Avg: 9ms / 38ms / 11.4ms
  Success:     100%

--- Summary for google.com ---           ← printed when google.com finishes
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
Duration:       00h 00m 12s 483ms
Hosts Tested:   4
Total Sent:     4000
Total Received: 3997
Overall Loss:   0.08%
========================================

Total execution time: 00h 00m 12s 483ms
Results exported to: .\PingResults_20260713_135203.csv
```

### CSV

A file named `PingResults_20260707_163209.csv` is saved in the same folder as the script.

| Hostname | Sent | Received | Lost | LossPercent | MinTime_ms | MaxTime_ms | AvgTime_ms | SuccessRate | UniqueErrors |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| google.com | 1000 | 1000 | 0 | 0 | 11 | 45 | 13.2 | 100 | 0 |
| 1.1.1.1 | 1000 | 998 | 2 | 0.2 | 8 | 60 | 9.1 | 99.8 | 0 |

---

## How It Works

```text
Script starts
     │
     ├─ Validate all hostnames (regex check)
     │
     ├─ Create synchronized hashtable (shared ping counter)
     │
     ├─ Create RunspacePool (1 slot per host)
     │
     ├─ BeginInvoke() — all hosts start pinging at the same time
     │      ├─ host 1: ping loop → writes counter to shared hashtable after every ping
     │      ├─ host 2: ping loop → writes counter to shared hashtable after every ping
     │      └─ host N: ping loop → writes counter to shared hashtable after every ping
     │
     ├─ Main thread polls every 200ms:
     │      ├─ Reads each host's counter → updates its live progress bar
     │      └─ If a host's handle is complete → print summary immediately, clear its bar
     │
     ├─ Repeat until all hosts reported
     │
     ├─ Print overall summary to console
     │
     └─ Export results to CSV
```

### Live counter mechanism

| Component | Role |
| --- | --- |
| `[hashtable]::Synchronized(@{})` | Thread-safe hashtable shared between main thread and all runspaces |
| `$SharedState[$Hostname] = $i` | Each runspace writes its current ping number after every single ping |
| 200ms poll loop | Main thread reads the counter and updates `Write-Progress` for each host |
| `$job.Handle.IsCompleted` | Main thread detects when a host is done and prints its summary immediately |

Each runspace:

1. Creates its own `System.Net.NetworkInformation.Ping` socket
2. Sends `$PingCount` ICMP echo requests, recording round-trip time for each success
3. After every ping, writes the current count to the shared hashtable so the main thread can display it
4. Calculates loss %, success rate, min/max/avg latency
5. Returns a stats object back to the main thread via `EndInvoke`

---

## Files

```text
Ping_multihosts/
├── Ping-HostnameTest.ps1        # Main script
└── PingResults_<timestamp>.csv  # Auto-generated on each run (gitignored)
```
