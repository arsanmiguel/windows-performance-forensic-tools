# PowerShell Utilities for Windows Performance Diagnostics

## Overview

A collection of PowerShell utilities designed to help system administrators, DBAs, and engineers diagnose Windows Server performance issues. Originally created for AWS DMS migrations, these tools are useful for any Windows performance troubleshooting scenario.

**Key Features:**
- ✅ Automated performance counter collection
- ✅ Disk I/O performance analysis
- ✅ CPU, Memory, and Network diagnostics
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

### **1. ps-getperfcounters.ps1**
Comprehensive performance counter collection with automatic AWS Support case creation.

**What it does:**
- Resets and resyncs Windows performance counters
- Collects disk, CPU, memory, and network metrics
- Analyzes bottlenecks automatically
- **Creates AWS Support case with all diagnostic data**

**Usage:**
```powershell
.\ps-getperfcounters.ps1
```

**Output:**
- Performance counter results file: `perfmon_results-[timestamp].txt`
- AWS Support case ID (if bottlenecks detected)
- Diagnostic summary

---

### **2. Measure-DiskPerformance.ps1**
Detailed disk I/O performance analysis.

**Usage:**
```powershell
.\Measure-DiskPerformance.ps1
```

---

## 🎯 **Use Cases**

### **AWS DMS Migrations**
Diagnose source database server performance issues during migration:
```powershell
# Run during migration to capture performance data
.\ps-getperfcounters.ps1
```

### **SQL Server Performance Issues**
Identify disk, CPU, or memory bottlenecks:
```powershell
# Collect metrics during problem period
.\ps-getperfcounters.ps1
```

### **Right-Sizing Exercises**
Gather baseline performance data for capacity planning:
```powershell
# Run multiple times to establish baseline
.\Measure-DiskPerformance.ps1
```

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

## 📋 **Performance Counters Collected**

### **Disk Metrics**
- % Idle Time
- Avg. Disk sec/Read
- Avg. Disk sec/Write
- Disk Queue Length
- Disk Transfers/sec

### **CPU Metrics**
- % Processor Time
- % Privileged Time
- % User Time
- DPCs Queued/sec

### **Memory Metrics**
- Available Bytes
- Pages/sec

### **Network Metrics**
- Bytes Total/sec
- Output Queue Length

---

## 🛠️ **Troubleshooting**

### **Performance Counters Not Working**
```powershell
# Reset counters manually
cd c:\windows\system32
lodctr /R
cd c:\windows\sysWOW64
lodctr /R
winmgmt.exe /resyncperf
```

### **AWS Support Case Creation Fails**
- Verify AWS CLI is installed: `aws --version`
- Check credentials: `aws sts get-caller-identity`
- Ensure Support plan is active (Business or Enterprise)

### **Permission Denied Errors**
Run PowerShell as Administrator:
```powershell
Start-Process powershell -Verb runAs
```

---

## 📖 **Examples**

### **Basic Performance Check**
```powershell
# Collect performance data
.\ps-getperfcounters.ps1

# Output: perfmon_results-13-01-2026-19-30-00.txt
# AWS Support Case: case-123456789
```

### **Disk Performance Analysis**
```powershell
# Detailed disk metrics
.\Measure-DiskPerformance.ps1
```

---

## 🔍 **Understanding the Output**

### **Performance Counter Results**
```
Category    Counter                    Instance    Value
--------    -------                    --------    -----
PhysicalDisk % Idle Time               C:          45
PhysicalDisk Avg. Disk sec/Read        C:          0.025
Memory      Available Bytes            -           2147483648
```

### **Bottleneck Detection**
The tool automatically identifies:
- **High disk latency** (>20ms read/write)
- **Low memory** (<10% available)
- **CPU saturation** (>80% sustained)
- **Network congestion** (high queue length)

---

## 📦 **What's Included**

- `ps-getperfcounters.ps1` - Main diagnostic tool with AWS Support integration
- `Measure-DiskPerformance.ps1` - Disk I/O analysis utility
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
- Performance counter collection may impact system performance slightly
- Tested on Windows Server 2012 R2 through 2022
- Works on AWS EC2, Azure VMs, GCP Compute, and on-premises
- **No warranty or official support provided** - use at your own discretion

---

## 📝 **Version History**

- **v2.0** (January 2026) - Added AWS Support API integration
- **v1.0** (February 2022) - Initial release

---

**Note:** These tools are provided as-is for diagnostic purposes. Always test in non-production environments first.
