<#
.SYNOPSIS
    Windows Performance Counter Collection with AWS Support Integration

.DESCRIPTION
    This script collects comprehensive performance metrics from Windows servers and can automatically
    create AWS Support cases when bottlenecks are detected. Originally designed for AWS DMS migrations,
    it's useful for any Windows performance troubleshooting scenario.

.PARAMETER CreateSupportCase
    Automatically create an AWS Support case if performance issues are detected

.PARAMETER Severity
    Support case severity: 'low', 'normal', 'high', 'urgent', 'critical'

.PARAMETER SampleInterval
    Interval in seconds between performance counter samples (default: 3)

.EXAMPLE
    .\ps-getperfcounters.ps1
    Collect performance data without creating support case

.EXAMPLE
    .\ps-getperfcounters.ps1 -CreateSupportCase -Severity high
    Collect data and create high-severity support case if issues detected

.NOTES
    Requires Administrator privileges and AWS CLI configured for support case creation
#>

[CmdletBinding()]
param(
    [switch]$CreateSupportCase,
    [ValidateSet('low', 'normal', 'high', 'urgent', 'critical')]
    [string]$Severity = 'normal',
    [int]$SampleInterval = 3
)

# Ensure running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

Write-Host "`n=== Windows Performance Diagnostics Tool ===" -ForegroundColor Cyan
Write-Host "Starting performance counter collection...`n" -ForegroundColor Green

# Reset and resync performance counters
Write-Host "[1/5] Resetting performance counters..." -ForegroundColor Yellow
try {
    Push-Location c:\windows\system32
    lodctr /R | Out-Null
    Pop-Location
    
    Push-Location c:\windows\sysWOW64
    lodctr /R | Out-Null
    Pop-Location
    
    winmgmt.exe /resyncperf | Out-Null
    
    Get-Service -Name "pla" | Restart-Service -Force -ErrorAction SilentlyContinue | Out-Null
    Get-Service -Name "winmgmt" | Restart-Service -Force -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "   Performance counters reset successfully" -ForegroundColor Green
    Start-Sleep -Seconds 2
} catch {
    Write-Warning "   Failed to reset some counters: $_"
}

# Define performance counters
Write-Host "[2/5] Defining performance counters..." -ForegroundColor Yellow
$counters = @(
    '\PhysicalDisk(*)\% Idle Time'
    '\PhysicalDisk(*)\Avg. Disk sec/Read'
    '\PhysicalDisk(*)\Avg. Disk sec/Write'
    '\PhysicalDisk(*)\Avg. Disk sec/Transfer'
    '\PhysicalDisk(*)\Disk Reads/sec'
    '\PhysicalDisk(*)\Disk Writes/sec'
    '\PhysicalDisk(*)\Disk Transfers/sec'
    '\PhysicalDisk(*)\Current Disk Queue Length'
    '\PhysicalDisk(*)\Avg. Disk Queue Length'
    '\Processor(*)\% Processor time'
    '\Processor(*)\% Privileged time'
    '\Processor(*)\% user time'
    '\Processor(*)\% idle time'
    '\Processor(*)\DPCs Queued/sec'
    '\Memory\Available Bytes'
    '\Memory\Pages/sec'
    '\Network Interface(*)\Bytes Total/sec'
    '\Network Interface(*)\Output Queue Length'
)
Write-Host "   Monitoring $($counters.Count) performance counters" -ForegroundColor Green

# Collect performance samples
Write-Host "[3/5] Collecting performance data (this takes ~$($SampleInterval * 3) seconds)..." -ForegroundColor Yellow
$samples = foreach ($counter in $counters) {
    try {
        $sample = (Get-Counter -Counter $counter -SampleInterval $SampleInterval -MaxSamples 3 -ErrorAction SilentlyContinue).CounterSamples
        foreach ($s in $sample) {
            [pscustomobject]@{
                Category = $s.Path.Split('\')[3]
                Counter = $s.Path.Split('\')[4]
                Instance = $s.InstanceName
                Value = [math]::Round($s.CookedValue, 2)
                Timestamp = $s.Timestamp
            }
        }
    } catch {
        Write-Warning "   Failed to collect counter: $counter"
    }
}

Write-Host "   Collected $($samples.Count) data points" -ForegroundColor Green

# Save results to file
$filename = "perfmon_results-" + (Get-Date).ToString("dd-MM-yyyy-HH-mm-ss") + ".txt"
Write-Host "[4/5] Saving results to: $filename" -ForegroundColor Yellow

$output = @"
===========================================
Windows Performance Counter Results
===========================================
Generated: $(Get-Date)
Computer: $env:COMPUTERNAME
OS: $(Get-WmiObject Win32_OperatingSystem | Select-Object -ExpandProperty Caption)
===========================================

"@

$output += $samples | Format-Table -AutoSize | Out-String
$output | Out-File $filename -Encoding UTF8

Write-Host "   Results saved successfully" -ForegroundColor Green

# Analyze for bottlenecks
Write-Host "[5/5] Analyzing performance data..." -ForegroundColor Yellow
$bottlenecks = @()

# Check disk latency (>20ms is concerning)
$diskReadLatency = $samples | Where-Object { $_.Counter -eq 'Avg. Disk sec/Read' -and $_.Instance -ne '_Total' } | 
    Measure-Object -Property Value -Average | Select-Object -ExpandProperty Average
if ($diskReadLatency -gt 0.020) {
    $bottlenecks += "High disk read latency: $([math]::Round($diskReadLatency * 1000, 2))ms (threshold: 20ms)"
}

$diskWriteLatency = $samples | Where-Object { $_.Counter -eq 'Avg. Disk sec/Write' -and $_.Instance -ne '_Total' } | 
    Measure-Object -Property Value -Average | Select-Object -ExpandProperty Average
if ($diskWriteLatency -gt 0.020) {
    $bottlenecks += "High disk write latency: $([math]::Round($diskWriteLatency * 1000, 2))ms (threshold: 20ms)"
}

# Check disk queue length (>2 is concerning)
$diskQueue = $samples | Where-Object { $_.Counter -eq 'Current Disk Queue Length' -and $_.Instance -ne '_Total' } | 
    Measure-Object -Property Value -Average | Select-Object -ExpandProperty Average
if ($diskQueue -gt 2) {
    $bottlenecks += "High disk queue length: $([math]::Round($diskQueue, 2)) (threshold: 2)"
}

# Check CPU utilization (>80% is concerning)
$cpuUsage = $samples | Where-Object { $_.Counter -eq '% Processor time' -and $_.Instance -eq '_Total' } | 
    Measure-Object -Property Value -Average | Select-Object -ExpandProperty Average
if ($cpuUsage -gt 80) {
    $bottlenecks += "High CPU utilization: $([math]::Round($cpuUsage, 2))% (threshold: 80%)"
}

# Check available memory (<10% is concerning)
$totalMemory = (Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory
$availableMemory = $samples | Where-Object { $_.Counter -eq 'Available Bytes' } | 
    Measure-Object -Property Value -Average | Select-Object -ExpandProperty Average
$memoryPercentAvailable = ($availableMemory / $totalMemory) * 100
if ($memoryPercentAvailable -lt 10) {
    $bottlenecks += "Low available memory: $([math]::Round($memoryPercentAvailable, 2))% (threshold: 10%)"
}

# Check memory paging (>10 pages/sec is concerning)
$pagesPerSec = $samples | Where-Object { $_.Counter -eq 'Pages/sec' } | 
    Measure-Object -Property Value -Average | Select-Object -ExpandProperty Average
if ($pagesPerSec -gt 10) {
    $bottlenecks += "High memory paging: $([math]::Round($pagesPerSec, 2)) pages/sec (threshold: 10)"
}

# Display results
Write-Host "`n=== Analysis Results ===" -ForegroundColor Cyan
if ($bottlenecks.Count -eq 0) {
    Write-Host "No significant performance bottlenecks detected." -ForegroundColor Green
} else {
    Write-Host "Performance issues detected:" -ForegroundColor Red
    foreach ($bottleneck in $bottlenecks) {
        Write-Host "  - $bottleneck" -ForegroundColor Yellow
    }
}

# Create AWS Support case if requested and bottlenecks found
if ($CreateSupportCase -and $bottlenecks.Count -gt 0) {
    Write-Host "`n=== Creating AWS Support Case ===" -ForegroundColor Cyan
    
    # Check if AWS CLI is available
    try {
        $awsVersion = aws --version 2>&1
        Write-Host "AWS CLI detected: $awsVersion" -ForegroundColor Green
    } catch {
        Write-Error "AWS CLI not found. Please install AWS CLI to create support cases."
        Write-Host "`nResults saved to: $filename" -ForegroundColor Cyan
        exit 1
    }
    
    # Gather system information
    $osInfo = Get-WmiObject Win32_OperatingSystem
    $computerInfo = Get-WmiObject Win32_ComputerSystem
    $instanceId = (Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/instance-id -TimeoutSec 2 -ErrorAction SilentlyContinue)
    
    # Build case description
    $caseSubject = "Windows Performance Issues Detected - $env:COMPUTERNAME"
    $caseDescription = @"
Automated performance diagnostics detected the following issues:

BOTTLENECKS DETECTED:
$($bottlenecks | ForEach-Object { "- $_" } | Out-String)

SYSTEM INFORMATION:
- Computer Name: $env:COMPUTERNAME
- OS: $($osInfo.Caption) $($osInfo.Version)
- Total Memory: $([math]::Round($totalMemory / 1GB, 2)) GB
- CPU Cores: $($computerInfo.NumberOfLogicalProcessors)
- Instance ID: $(if ($instanceId) { $instanceId } else { "Not an EC2 instance" })

PERFORMANCE SUMMARY:
- Average CPU Usage: $([math]::Round($cpuUsage, 2))%
- Available Memory: $([math]::Round($memoryPercentAvailable, 2))%
- Disk Read Latency: $([math]::Round($diskReadLatency * 1000, 2))ms
- Disk Write Latency: $([math]::Round($diskWriteLatency * 1000, 2))ms
- Disk Queue Length: $([math]::Round($diskQueue, 2))

Detailed performance counter data is attached.

Generated by: ps-getperfcounters.ps1
Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

    # Create support case
    Write-Host "Creating support case with severity: $Severity" -ForegroundColor Yellow
    
    $caseJson = @{
        subject = $caseSubject
        serviceCode = "amazon-ec2-windows"
        severityCode = $Severity
        categoryCode = "performance"
        communicationBody = $caseDescription
        language = "en"
        issueType = "technical"
    } | ConvertTo-Json
    
    try {
        # Create the case
        $caseResult = aws support create-case --cli-input-json $caseJson 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $caseId = ($caseResult | ConvertFrom-Json).caseId
            Write-Host "Support case created successfully!" -ForegroundColor Green
            Write-Host "Case ID: $caseId" -ForegroundColor Cyan
            
            # Attach performance data file
            Write-Host "Attaching performance data..." -ForegroundColor Yellow
            $attachmentContent = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path $filename)))
            
            $attachmentJson = @{
                attachments = @(
                    @{
                        fileName = $filename
                        data = $attachmentContent
                    }
                )
            } | ConvertTo-Json -Depth 3
            
            $attachmentSet = aws support add-attachments-to-set --cli-input-json $attachmentJson 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $attachmentSetId = ($attachmentSet | ConvertFrom-Json).attachmentSetId
                
                # Add attachment to case
                aws support add-communication-to-case --case-id $caseId --communication-body "Performance counter data attached." --attachment-set-id $attachmentSetId | Out-Null
                
                Write-Host "Performance data attached successfully" -ForegroundColor Green
            }
            
            Write-Host "`nYou can view your case at: https://console.aws.amazon.com/support/home#/case/?displayId=$caseId" -ForegroundColor Cyan
        } else {
            Write-Error "Failed to create support case: $caseResult"
        }
    } catch {
        Write-Error "Error creating support case: $_"
        Write-Host "Please ensure you have:"
        Write-Host "  1. AWS CLI configured (aws configure)"
        Write-Host "  2. Active AWS Support plan (Business or Enterprise)"
        Write-Host "  3. IAM permissions for support:CreateCase"
    }
}

# Final summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Performance data saved to: $filename" -ForegroundColor Green
if ($bottlenecks.Count -gt 0) {
    Write-Host "Bottlenecks detected: $($bottlenecks.Count)" -ForegroundColor Yellow
    if (-not $CreateSupportCase) {
        Write-Host "`nTip: Run with -CreateSupportCase to automatically open an AWS Support case" -ForegroundColor Cyan
    }
} else {
    Write-Host "System performance looks healthy" -ForegroundColor Green
}
Write-Host ""
