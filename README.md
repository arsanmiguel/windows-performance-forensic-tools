# Windows Performance Forensic Tools

## Overview

A collection of PowerShell utilities designed to help system administrators, DBAs, and engineers diagnose Windows Server performance issues. Originally created for AWS DMS migrations, these tools are useful for any Windows performance troubleshooting scenario.

**Key Features:**
- ✅ Comprehensive performance forensics (CPU, Memory, Disk, Network, Database)
- ✅ Automated bottleneck detection
- ✅ Disk I/O performance testing (no external tools required)
- ✅ CPU forensics (thread analysis, throttling detection)
- ✅ Memory forensics (leak detection, page file analysis)
- ✅ **Database forensics** (SQL Server, MySQL, PostgreSQL, MongoDB, Redis, Cassandra, Oracle, Elasticsearch)
  <details>
  <summary>DBA-level query analysis capabilities</summary>
  
  - Top 5 queries by CPU/time, long-running queries (>30s), blocking detection
  - **SQL Server/MySQL/PostgreSQL**: DMV/performance schema queries, active sessions, wait states
  - **MongoDB**: currentOp() and profiler analysis for slow operations
  - **Redis**: SLOWLOG, ops/sec metrics, connection rejection tracking
  - **Oracle**: v$session and v$sql analysis, blocking session detection
  - **Elasticsearch**: Tasks API for long-running searches, thread pool monitoring
  </details>
- ✅ **Automatic AWS Support case creation** with diagnostic data
- ✅ Works across all hyperscalers and on-premises

---

## 🚀 **Quick Start**

### **Prerequisites**
- Windows Server 2012 R2 or later
- PowerShell 5.1 or later
- Administrator privileges
- AWS CLI configured (for automatic support case creation)

### **Installation**

1. **Clone the repository:**
```powershell
git clone https://github.com/arsanmiguel/windows-performance-forensic-tools.git
cd windows-performance-forensic-tools
```

2. **Set execution policy (if needed):**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 📊 **Available Tools**

### **Invoke-WindowsForensics.ps1** (NEW)
**A complete Windows performance diagnostic tool** - comprehensive forensics with automatic issue detection.

<details>
<summary><strong>What it does</strong></summary>

- Collects performance counters (disk, CPU, memory, network)
- Performs real disk I/O testing
- Analyzes CPU usage, threads, and throttling
- Detects memory leaks and paging issues
- **Detects and analyzes database bottlenecks** (SQL Server, MySQL, PostgreSQL, MongoDB, Redis, Cassandra, Oracle, Elasticsearch)
  - Top 5 queries by CPU time and resource consumption (all platforms)
  - Long-running queries/operations (>30 seconds)
  - Blocking and wait state analysis (SQL Server, Oracle)
  - Connection pool exhaustion and rejection tracking (all platforms)
  - Thread pool monitoring (Elasticsearch)
  - Slow operation profiling (MongoDB, Redis)
- **Automatically identifies bottlenecks**
- **Creates AWS Support case** with all diagnostic data

</details>

<details>
<summary><strong>Usage</strong></summary>

```powershell
# Quick diagnostics (3 minutes)
.\Invoke-WindowsForensics.ps1 -Mode Quick

# Standard diagnostics (5-10 minutes)
.\Invoke-WindowsForensics.ps1 -Mode Standard

# Deep diagnostics (15-20 minutes)
.\Invoke-WindowsForensics.ps1 -Mode Deep

# Auto-create support case if issues found
.\Invoke-WindowsForensics.ps1 -Mode Standard -CreateSupportCase -Severity high

# Disk-only diagnostics
.\Invoke-WindowsForensics.ps1 -Mode DiskOnly -DiskTestSize 5

# CPU-only diagnostics
.\Invoke-WindowsForensics.ps1 -Mode CPUOnly

# Memory-only diagnostics
.\Invoke-WindowsForensics.ps1 -Mode MemoryOnly
```

</details>

<details>
<summary><strong>Output Example</strong></summary>

```
BOTTLENECKS DETECTED: 3 performance issue(s) found

  CRITICAL ISSUES (1):
    • Memory: Low available memory

  HIGH PRIORITY (2):
    • Disk: High write latency
    • CPU: High CPU utilization

Detailed report saved to: windows-forensics-20260113-193000.txt
AWS Support case created: case-123456789
```

</details>

---

## 📖 **Examples**

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

---

## 🎯 **Use Cases**

<details>
<summary><strong>AWS DMS Migrations</strong></summary>

Diagnose source database server performance issues:
```powershell
# Run during migration to capture comprehensive diagnostics
.\Invoke-WindowsForensics.ps1 -Mode Deep -CreateSupportCase
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

---

## **What Bottlenecks Can Be Found?**

The tool automatically detects:

<details>
<summary><strong>Disk Issues</strong></summary>

- High read/write latency (>20ms)
- Excessive disk queue length (>2)
- Poor I/O performance

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

**Supported Databases:**
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

---

## 🔧 **Configuration**

### **AWS Support Integration**

The tools can automatically create AWS Support cases when performance issues are detected.

<details>
<summary><strong>Setup Instructions</strong></summary>

**Setup:**
1. **Install AWS CLI:**
```powershell
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

2. **Configure AWS credentials:**
```powershell
aws configure
```

3. **Verify Support API access:**
```powershell
aws support describe-services
```

**Required IAM Permissions:**
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

## 🛠️ **Troubleshooting**

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

---

## 📦 **What's Included**

- `Invoke-WindowsForensics.ps1` - **NEW!** Comprehensive forensics tool with bottleneck detection
- `ps-getperfcounters.ps1` - Legacy performance counter tool
- `Measure-DiskPerformance.ps1` - Legacy disk testing tool
- `README.md` - This documentation

---

## 🤝 **Support**

### **Contact**
- **Report bugs and feature requests:** [adrianrs@amazon.com](mailto:adrianrs@amazon.com)

### **AWS Support**
For AWS-specific issues, the tool can automatically create support cases with diagnostic data attached.

---

## ⚠️ **Important Notes**

- These utilities require Administrator privileges
- Disk testing may impact system performance temporarily
- Tested on Windows Server 2012 R2 through 2022
- Works on AWS EC2, Azure VMs, GCP Compute, and on-premises
- **No warranty or official support provided** - use at your own discretion

---

## 📝 **Version History**

- **v2.0** (January 2026) - Complete rewrite with unified forensics tool, automatic bottleneck detection, CPU/Memory forensics
- **v1.5** (January 2026) - Added AWS Support API integration
- **v1.0** (February 2022) - Initial release

---

**Note:** These tools are provided as-is for diagnostic purposes. Always test in non-production environments first.
