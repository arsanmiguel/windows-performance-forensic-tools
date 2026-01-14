# PowerShell Utilities for Windows Performance Diagnostics

## Overview

A collection of PowerShell utilities designed to help system administrators, DBAs, and engineers diagnose Windows Server performance issues. Originally created for AWS DMS migrations, these tools are useful for any Windows performance troubleshooting scenario.

**Key Features:**
- ✅ Comprehensive performance forensics (CPU, Memory, Disk, Network)
- ✅ Automated bottleneck detection ("Here be dragons" 🐉)
- ✅ Disk I/O performance testing (no external tools required)
- ✅ CPU forensics (thread analysis, throttling detection)
- ✅ Memory forensics (leak detection, page file analysis)
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
git clone https://github.com/arsanmiguel/ps_utilities.git
cd ps_utilities
```

2. **Set execution policy (if needed):**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 📊 **Available Tools**

### **1. Invoke-WindowsForensics.ps1** ⭐ NEW!
**The ultimate Windows performance diagnostic tool** - comprehensive forensics with automatic issue detection.

**What it does:**
- Collects performance counters (disk, CPU, memory, network)
- Performs real disk I/O testing
- Analyzes CPU usage, threads, and throttling
- Detects memory leaks and paging issues
- **Automatically identifies bottlenecks** ("Here be dragons" 🐉)
- **Creates AWS Support case** with all diagnostic data

**Usage:**
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

**Output:**
```
🐉 DRAGONS DETECTED: 3 performance issue(s) found

  CRITICAL ISSUES (1):
    • Memory: Low available memory

  HIGH PRIORITY (2):
    • Disk: High write latency
    • CPU: High CPU utilization

Detailed report saved to: windows-forensics-20260113-193000.txt
AWS Support case created: case-123456789
```

---

### **2. ps-getperfcounters.ps1** (Legacy)
Original performance counter collection tool with AWS Support integration.

**Usage:**
```powershell
.\ps-getperfcounters.ps1 -CreateSupportCase -Severity high
```

---

### **3. Measure-DiskPerformance.ps1** (Legacy)
Original disk I/O testing tool (requires SQLIO.exe).

---

## 🎯 **Use Cases**

### **AWS DMS Migrations**
Diagnose source database server performance issues:
```powershell
# Run during migration to capture comprehensive diagnostics
.\Invoke-WindowsForensics.ps1 -Mode Deep -CreateSupportCase
```

### **SQL Server Performance Issues**
Identify all bottlenecks automatically:
```powershell
# Standard mode is perfect for SQL Server diagnostics
.\Invoke-WindowsForensics.ps1 -Mode Standard
```

### **Right-Sizing Exercises**
Gather baseline performance data:
```powershell
# Quick mode for rapid assessment
.\Invoke-WindowsForensics.ps1 -Mode Quick
```

### **Production Issue Troubleshooting**
When things go wrong:
```powershell
# Deep mode + auto support case
.\Invoke-WindowsForensics.ps1 -Mode Deep -CreateSupportCase -Severity urgent
```

---

## 🐉 **What Dragons Can Be Found?**

The tool automatically detects:

### **Disk Issues**
- High read/write latency (>20ms)
- Excessive disk queue length (>2)
- Poor I/O performance

### **CPU Issues**
- High CPU utilization (>80%)
- CPU throttling
- Excessive context switches (>15,000/sec)
- High processor queue length (>2)
- Excessive thread counts

### **Memory Issues**
- Low available memory (<10%)
- High memory paging (>10 pages/sec)
- High page fault rate (>1,000/sec)
- Memory leaks (high virtual memory usage)
- High page file usage (>80%)
- High committed memory (>90%)

### **Network Issues**
- High TCP retransmissions (>10/sec)
- Network packet errors

---

## 🔧 **Configuration**

### **AWS Support Integration**

The tools can automatically create AWS Support cases when performance issues are detected.

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

---

## 📖 **Examples**

### **Example 1: Quick Health Check**
```powershell
.\Invoke-WindowsForensics.ps1 -Mode Quick
```
Output: 3-minute assessment with automatic dragon detection

### **Example 2: Production Issue with Auto-Ticket**
```powershell
.\Invoke-WindowsForensics.ps1 -Mode Deep -CreateSupportCase -Severity urgent
```
Output: Comprehensive diagnostics + AWS Support case with all data attached

### **Example 3: Disk Performance Testing**
```powershell
.\Invoke-WindowsForensics.ps1 -Mode DiskOnly -DiskTestSize 10
```
Output: Detailed disk I/O testing with 10GB test file

---

## 🛠️ **Troubleshooting**

### **Performance Counters Not Working**
The tool automatically resets counters, but if issues persist:
```powershell
cd c:\windows\system32
lodctr /R
cd c:\windows\sysWOW64
lodctr /R
winmgmt.exe /resyncperf
```

### **AWS Support Case Creation Fails**
- Verify AWS CLI: `aws --version`
- Check credentials: `aws sts get-caller-identity`
- Ensure Support plan is active (Business or Enterprise)

### **Permission Denied Errors**
Run PowerShell as Administrator:
```powershell
Start-Process powershell -Verb runAs
```

---

## 📦 **What's Included**

- `Invoke-WindowsForensics.ps1` - **NEW!** Comprehensive forensics tool with dragon detection
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

- **v2.0** (January 2026) - Complete rewrite with unified forensics tool, automatic dragon detection, CPU/Memory forensics
- **v1.5** (January 2026) - Added AWS Support API integration
- **v1.0** (February 2022) - Initial release

---

**Note:** These tools are provided as-is for diagnostic purposes. Always test in non-production environments first.
