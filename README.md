# Windows Performance Forensic Tools

<a id="overview"></a>
## Overview

A comprehensive PowerShell-based diagnostic tool for Windows servers that automatically detects performance bottlenecks and can create AWS Support cases with detailed forensic data. Originally created for AWS DMS migration troubleshooting; run on your SOURCE DATABASE SERVER. Now useful for any Windows performance troubleshooting; run on the machine you want to diagnose and optionally open an AWS Support case with full details attached.

Key Features:

- Performance forensics: CPU, memory, disk, network, database (performance counters, disk I/O, thread analysis)
- Storage profiling (partition schemes, dynamic disks, tiering, SMART health, SAN/iSCSI, EBS/Azure)
- AWS DMS source database diagnostics (binary logging, replication lag, connection analysis)
- Automated bottleneck detection
- Graceful degradation when tools unavailable
- Database forensics: DBA-level query analysis and DMS readiness checks
- Automatic AWS Support case creation with diagnostic data
- Works on Windows Server 2012 R2 or later; works across hyperscalers and on-premises

TL;DR - Run it now
```powershell
git clone https://github.com/arsanmiguel/win-forensics.git
cd win-forensics
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\Invoke-WindowsForensics.ps1 -Mode Quick
```
(Run PowerShell as Administrator for full diagnostics.) Then read on for AWS Support or troubleshooting.

Quick links: [Install](#installation) · [Usage](#available-tool) · [Troubleshooting](#troubleshooting)

Contents
- [Overview](#overview)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Examples](#examples)
- [Use Cases](#use-cases)
- [What Bottlenecks Can Be Found](#what-bottlenecks-can-be-found)
- [Troubleshooting](#troubleshooting)
- [Configuration (AWS Support)](#configuration)
- [Support](#support)
- [Important Notes & Performance](#important-notes-and-performance)
- [Version History](#version-history)

---

<a id="quick-start"></a>
## Quick Start

### Prerequisites
- Windows Server 2012 R2 or later
- PowerShell 5.1 or later
- Administrator privileges
- AWS CLI configured (for automatic support case creation)

<a id="installation"></a>
### Installation

1. Clone the repository:
```powershell
git clone https://github.com/arsanmiguel/win-forensics.git
cd win-forensics
```

2. Set execution policy (if needed):
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

<a id="available-tool"></a>
The script runs system diagnostics and writes a report to a timestamped file; optional AWS Support case creation when issues are found. Usage: `.\Invoke-WindowsForensics.ps1 -Mode Quick|Standard|Deep [-CreateSupportCase] [-Severity level]`.

---

<a id="examples"></a>
## Examples

Run as Administrator for full diagnostics.

<details>
<summary><strong>Example 1: Quick Health Check</strong></summary>

```powershell
.\Invoke-WindowsForensics.ps1 -Mode Quick
```
Output: 3-minute assessment with automatic bottleneck detection

</details>

<details>
<summary><strong>Example 2: Production Issue with Auto-Ticket</strong></summary>

```powershell
.\Invoke-WindowsForensics.ps1 -Mode Deep -CreateSupportCase -Severity urgent
```
Output: Comprehensive diagnostics + AWS Support case with all data attached

</details>

<details>
<summary><strong>Example 3: Disk Performance Testing</strong></summary>

```powershell
.\Invoke-WindowsForensics.ps1 -Mode DiskOnly -DiskTestSize 10
```
Output: Detailed disk I/O testing with 10GB test file

</details>

### Use Cases

<a id="use-cases"></a>
<details>
<summary><strong>Use Cases</strong> (DMS, SQL Server, right-sizing, production)</summary>

<details>
<summary><strong>AWS DMS Migrations</strong></summary>

This tool is designed to run on your SOURCE DATABASE SERVER, not on the DMS replication instance (which is AWS-managed).

What it checks for DMS by database type:

<details>
<summary><strong>MySQL/MariaDB</strong></summary>

- Binary logging enabled (log_bin=ON, required for CDC)
- Binlog format set to ROW (required for DMS)
- Binary log retention configured (expire_logs_days >= 1)
- Replication lag (if source is a replica)

</details>

<details>
<summary><strong>PostgreSQL</strong></summary>

- WAL level set to 'logical' (required for CDC)
- Replication slots configured (max_replication_slots >= 1)
- Replication lag (if standby server)

</details>

<details>
<summary><strong>Oracle</strong></summary>

- ARCHIVELOG mode enabled (required for CDC)
- Supplemental logging enabled (required for DMS)
- Data Guard apply lag (if standby)

</details>

<details>
<summary><strong>SQL Server</strong></summary>

- SQL Server Agent running (required for CDC)
- Database recovery model set to FULL (required for CDC)
- AlwaysOn replica lag (if applicable)

</details>

<details>
<summary><strong>All Databases</strong></summary>

- Database connection health
- Network connectivity to database ports
- Connection churn that could impact DMS
- Source database performance issues
- Long-running queries/sessions
- High connection counts

</details>

Run this when:
- Planning a DMS migration (pre-migration assessment)
- DMS replication is slow or stalling
- Source database performance issues
- High replication lag
- Connection errors in DMS logs
- CDC not capturing changes

Usage:
```powershell
.\Invoke-WindowsForensics.ps1 -Mode Deep -CreateSupportCase -Severity high
```

</details>

<details>
<summary><strong>SQL Server Performance Issues</strong></summary>

Identify all bottlenecks automatically:
```powershell
# Standard mode is perfect for SQL Server diagnostics
.\Invoke-WindowsForensics.ps1 -Mode Standard
```

</details>

<details>
<summary><strong>Right-Sizing Exercises</strong></summary>

Gather baseline performance data:
```powershell
# Quick mode for rapid assessment
.\Invoke-WindowsForensics.ps1 -Mode Quick
```

</details>

<details>
<summary><strong>Production Issue Troubleshooting</strong></summary>

When things go wrong:
```powershell
# Deep mode + auto support case
.\Invoke-WindowsForensics.ps1 -Mode Deep -CreateSupportCase -Severity urgent
```

</details>

</details>

### What Bottlenecks Can Be Found

<a id="what-bottlenecks-can-be-found"></a>
<details>
<summary><strong>What Bottlenecks Can Be Found?</strong> (What the script can detect)</summary>

The tool automatically detects:

<details>
<summary><strong>Disk Issues</strong></summary>

- High read/write latency (>20ms)
- Excessive disk queue length (>2)
- Poor I/O performance

</details>

<details>
<summary><strong>Storage Issues</strong></summary>

- Misaligned partitions (4K alignment check - 30-50% perf loss on SSD/SAN)
- MBR partition on >2TB disk (only 2TB usable - data loss risk)
- Degraded dynamic disk volumes (mirrored/RAID-5 with failed member)
- Dynamic disk health issues (status not OK)
- RAW/uninitialized disks detected
- Disk health issues (SMART failures, unhealthy status)
- High SSD wear level (>80%)
- High disk temperature (>60°C)
- Storage Spaces pool health issues
- AWS EBS gp2 volumes detected (recommend upgrade to gp3)
- Failed iSCSI sessions
- MPIO path failures

</details>

<details>
<summary><strong>CPU Issues</strong></summary>

- High CPU utilization (>80%)
- CPU throttling
- Excessive context switches (>15,000/sec)
- High processor queue length (>2)
- Excessive thread counts

</details>

<details>
<summary><strong>Memory Issues</strong></summary>

- Low available memory (<10%)
- High memory paging (>10 pages/sec)
- High page fault rate (>1,000/sec)
- Memory leaks (high virtual memory usage)
- High page file usage (>80%)
- High committed memory (>90%)

</details>

<details>
<summary><strong>Database Issues</strong></summary>

- High connection count (SQL Server/MySQL/PostgreSQL/Oracle: >500, MongoDB/Cassandra: >1000, Redis: >10,000)
- High connection churn (>1,000 TIME_WAIT connections on database ports)
- Excessive resource usage by database processes
- Top 5 queries by CPU/time, long-running queries (>30s), blocking detection
- SQL Server/MySQL/PostgreSQL: DMV/performance schema queries, active sessions, wait states
- MongoDB: currentOp() and profiler analysis for slow operations
- Redis: SLOWLOG, ops/sec metrics, connection rejection tracking
- Oracle: v$session and v$sql analysis, blocking session detection
- Elasticsearch: Tasks API for long-running searches, thread pool monitoring

Supported Databases:
- SQL Server
- MySQL / MariaDB
- PostgreSQL
- MongoDB
- Redis
- Cassandra
- Oracle Database
- Elasticsearch

</details>

<details>
<summary><strong>Network Issues</strong></summary>

- High TCP retransmissions (>10/sec)
- Network packet errors

</details>

</details>

---

<a id="troubleshooting"></a>
## Troubleshooting

<details>
<summary><strong>Performance Counters Not Working</strong></summary>

The tool automatically resets counters, but if issues persist:
```powershell
cd c:\windows\system32
lodctr /R
cd c:\windows\sysWOW64
lodctr /R
winmgmt.exe /resyncperf
```

</details>

<details>
<summary><strong>AWS Support Case Creation Fails</strong></summary>

- Verify AWS CLI: `aws --version`
- Check credentials: `aws sts get-caller-identity`
- Ensure Support plan is active (Business or Enterprise)

</details>

<details>
<summary><strong>Permission Denied Errors</strong></summary>

Run PowerShell as Administrator:
```powershell
Start-Process powershell -Verb runAs
```

</details>

<details>
<summary><strong>Storage Profiling</strong></summary>

The script uses native Windows tools and cmdlets for storage analysis:

| Cmdlet/Tool | Purpose |
|-------------|---------|
| Get-PhysicalDisk | Physical disk information and health |
| Get-Disk | Disk configuration, partition style (GPT/MBR/RAW) |
| Get-Partition | Partition layout and types (ESP, MSR, Recovery, LDM) |
| Get-Volume | Volume information, filesystem type |
| Get-StoragePool | Storage Spaces pools |
| Get-StorageReliabilityCounter | SMART/reliability data (wear, temperature, errors) |
| Get-IscsiSession | iSCSI sessions |
| Get-IscsiTarget | iSCSI targets |
| diskpart | Dynamic disk/volume details (mirrored, striped, RAID-5) |
| Win32_DiskPartition | Dynamic disk detection (Logical Disk Manager) |
| bcdedit | Boot configuration (UEFI/BIOS detection) |

Partition Scheme Detection:
- GPT (GUID Partition Table) - Modern, UEFI, supports >2TB
- MBR (Master Boot Record) - Legacy, BIOS, 2TB limit
- RAW - Uninitialized disk (warning generated)

Partition Alignment Analysis:
- Checks all partitions for 4K (4096 byte) alignment
- Identifies 1MB alignment (optimal for SSD/SAN)
- Calculates offset in KB and sectors
- Severity based on storage type:
  - SSD/NVMe: High severity (30-50% performance loss)
  - SAN (iSCSI/FC): High severity (30-50% loss + backend I/O amplification)
  - HDD: Medium severity (10-20% loss from read-modify-write)
- Common cause: Partitions created on Windows XP/Server 2003 (63-sector offset)
- Windows Vista+ and Server 2008+ auto-align to 1MB by default

Partition Type Detection:
- EFI System Partition (ESP)
- Microsoft Reserved (MSR)
- Basic Data
- Windows Recovery
- Storage Spaces
- LDM Metadata/Data (dynamic disks)

Filesystem Detection:
- NTFS, ReFS, FAT32, exFAT
- Dev Drives (Windows 11 22H2+ performance volumes)

Dynamic Disk Analysis:
- Detects mirrored, striped, spanned, and RAID-5 volumes
- Identifies degraded or failed dynamic volumes
- Reports disk health status via WMI

For SAN environments:
- MPIO configuration: `Get-MSDSMAutomaticClaimSettings`
- Fibre Channel: WMI class `MSFC_FCAdapterHBAAttributes`

AWS EBS analysis requires:
- AWS CLI installed and configured
- IAM permissions for `ec2:DescribeVolumes`

</details>

---

<a id="configuration"></a>
## Configuration

### AWS Support Integration

The tools can automatically create AWS Support cases when performance issues are detected.

<details>
<summary><strong>Setup Instructions</strong></summary>

Setup:
1. Install AWS CLI:
```powershell
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

2. Configure AWS credentials:
```powershell
aws configure
```

3. Verify Support API access:
```powershell
aws support describe-services
```

Required IAM Permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "support:CreateCase",
        "support:AddAttachmentsToSet",
        "support:AddCommunicationToCase"
      ],
      "Resource": "*"
    }
  ]
}
```

</details>

---

---

<a id="support"></a>
## Support

### Contact
- Report bugs and feature requests: [adrianr.sanmiguel@gmail.com](mailto:adrianr.sanmiguel@gmail.com)

### AWS Support
For AWS-specific issues, the tool can automatically create support cases with diagnostic data attached.

---

<a id="important-notes-and-performance"></a>
## Important Notes & Performance

<details>
<summary><strong>Important Notes & Expected Performance Impact</strong></summary>

- These utilities require Administrator privileges
- Disk testing may impact system performance temporarily
- Tested on Windows Server 2012 R2 through 2022
- Works on AWS EC2, Azure VMs, GCP Compute, and on-premises
- No warranty or official support provided - use at your own discretion

### Expected Performance Impact

Quick Mode (3 minutes):
- CPU: <5% overhead - mostly reading performance counters
- Memory: <50MB - lightweight data collection
- Disk I/O: Minimal - no performance testing, only stat collection
- Network: None - passive monitoring only
- Safe for production - read-only operations

Standard Mode (5-10 minutes):
- CPU: 5-10% overhead - includes sampling and process analysis
- Memory: <100MB - additional process tree analysis
- Disk I/O: Minimal - no write testing, only extended stat collection
- Network: None - passive monitoring only
- Safe for production - read-only operations

Deep Mode (15-20 minutes):
- CPU: 10-20% overhead - includes extended sampling
- Memory: <150MB - comprehensive process and memory analysis
- Disk I/O: Moderate impact - performs disk read/write tests (configurable size)
- Network: None - passive monitoring only
- Use caution in production - disk tests may cause temporary I/O spikes
- Recommendation: Run during maintenance windows or low-traffic periods

Database Query Analysis (all modes):
- CPU: <2% overhead per database - lightweight queries to system tables
- Memory: <20MB per database - result set caching
- Database Load: Minimal - uses DMVs/performance schema/system views
- Safe for production - read-only queries, no table locks

General Guidelines:
- The tool is read-only except for disk write tests in deep mode
- No application restarts or configuration changes
- Performance counters sampled at regular intervals
- Database queries target system/performance tables only, not user data
- All operations are non-blocking and use minimal system resources

</details>

---

<a id="version-history"></a>
## Version History

<details>
<summary><strong>Version History</strong></summary>

- v2.2 (February 2026) - README overhaul
  - Structure and flow aligned with linux-forensics/unix-forensics: table of contents (Contents) with anchors, TL;DR, Quick links
  - Replaced long "Available Tools" section with a short blurb; Use Cases and What Bottlenecks are subsections of Examples
  - Section order: Troubleshooting before Configuration; Important Notes & Performance and Version History are collapsible
  - Removed emojis; slimmed Key Features; consistent section headers and styling; removed What's Included
- v2.1 (February 2026) - Storage profiling
  - Partition scheme analysis (GPT/MBR/RAW with warnings)
  - Partition type detection (ESP, MSR, Recovery, LDM, Storage Spaces)
  - Boot configuration (UEFI vs Legacy BIOS, Secure Boot)
  - Dynamic disk analysis (mirrored, striped, spanned, RAID-5)
  - Degraded volume detection
  - Filesystem detection (NTFS, ReFS, Dev Drives)
  - SMART/reliability monitoring
  - SAN/iSCSI/MPIO detection
  - AWS EBS and Azure disk optimization recommendations
- v2.0 (January 2026) - Complete rewrite with unified forensics tool, automatic bottleneck detection, CPU/Memory forensics
- v1.5 (January 2026) - AWS Support API integration
- v1.0 (February 2022) - Initial release

</details>

---

Note: These tools are provided as-is for diagnostic purposes. Always test in non-production environments first.
