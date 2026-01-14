<#
.SYNOPSIS
    Comprehensive Windows Performance Forensics Tool with AWS Support Integration

.DESCRIPTION
    A unified diagnostic tool that performs deep forensics on Windows servers including:
    - Performance counter collection
    - Disk I/O testing and analysis
    - CPU forensics (threads, context switches, interrupts)
    - Memory forensics (page faults, pool usage, leaks)
    - Network analysis (bandwidth, packet loss, retransmits)
    - System information gathering
    - Automatic bottleneck detection ("Here be dragons")
    - AWS Support case creation with comprehensive diagnostic data

.PARAMETER Mode
    Diagnostic mode: 'Quick', 'Standard', 'Deep', 'DiskOnly', 'CPUOnly', 'MemoryOnly'

.PARAMETER CreateSupportCase
    Automatically create AWS Support case if issues detected

.PARAMETER Severity
    Support case severity: 'low', 'normal', 'high', 'urgent', 'critical'

.PARAMETER OutputPath
    Path to save diagnostic results (default: current directory)

.PARAMETER DiskTestSize
    Size of disk test file in GB (default: 1)

.EXAMPLE
    .\Invoke-WindowsForensics.ps1 -Mode Quick
    Run quick diagnostics without support case

.EXAMPLE
    .\Invoke-WindowsForensics.ps1 -Mode Deep -CreateSupportCase -Severity high
    Run comprehensive diagnostics and create high-severity support case

.EXAMPLE
    .\Invoke-WindowsForensics.ps1 -Mode DiskOnly -DiskTestSize 5
    Run disk-only diagnostics with 5GB test file

.NOTES
    Requires Administrator privileges
    AWS CLI required for support case creation
    Version: 2.0
    Author: AWS Solutions Architecture
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Quick', 'Standard', 'Deep', 'DiskOnly', 'CPUOnly', 'MemoryOnly')]
    [string]$Mode = 'Standard',
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateSupportCase,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('low', 'normal', 'high', 'urgent', 'critical')]
    [string]$Severity = 'normal',
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = $PWD,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet(1, 5, 10, 50, 100)]
    [int]$DiskTestSize = 1
)

#Requires -RunAsAdministrator

# Global variables
$script:Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:OutputFile = Join-Path $OutputPath "windows-forensics-$script:Timestamp.txt"
$script:Bottlenecks = @()
$script:DiagnosticData = @{}

#region Helper Functions

Function Write-ForensicsLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Dragon')]
        [string]$Level = 'Info'
    )
    
    $colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
        'Dragon' = 'Magenta'
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    
    Write-Host $logMessage -ForegroundColor $colors[$Level]
    Add-Content -Path $script:OutputFile -Value $logMessage
}

Function Write-ForensicsHeader {
    param([string]$Title)
    
    $separator = "=" * 80
    Write-ForensicsLog "`n$separator" -Level Info
    Write-ForensicsLog "  $Title" -Level Info
    Write-ForensicsLog "$separator`n" -Level Info
}

Function Add-Bottleneck {
    param(
        [string]$Category,
        [string]$Issue,
        [string]$Value,
        [string]$Threshold,
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Impact = 'Medium'
    )
    
    $script:Bottlenecks += [PSCustomObject]@{
        Category = $Category
        Issue = $Issue
        CurrentValue = $Value
        Threshold = $Threshold
        Impact = $Impact
        Timestamp = Get-Date
    }
    
    Write-ForensicsLog "🐉 DRAGON FOUND: $Category - $Issue (Current: $Value, Threshold: $Threshold)" -Level Dragon
}

#endregion

#region System Information

Function Get-SystemInformation {
    Write-ForensicsHeader "SYSTEM INFORMATION"
    
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS
        
        # Try to get EC2 metadata
        $instanceId = $null
        $instanceType = $null
        $availabilityZone = $null
        
        try {
            $instanceId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" -TimeoutSec 2 -ErrorAction SilentlyContinue
            $instanceType = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-type" -TimeoutSec 2 -ErrorAction SilentlyContinue
            $availabilityZone = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/placement/availability-zone" -TimeoutSec 2 -ErrorAction SilentlyContinue
        } catch {
            Write-ForensicsLog "Not running on EC2 or metadata service unavailable" -Level Info
        }
        
        $sysInfo = @{
            ComputerName = $env:COMPUTERNAME
            OSName = $os.Caption
            OSVersion = $os.Version
            OSBuild = $os.BuildNumber
            OSArchitecture = $os.OSArchitecture
            LastBootTime = $os.LastBootUpTime
            Uptime = (Get-Date) - $os.LastBootUpTime
            TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            CPUName = $cpu.Name
            CPUCores = $cpu.NumberOfCores
            CPULogicalProcessors = $cpu.NumberOfLogicalProcessors
            Manufacturer = $cs.Manufacturer
            Model = $cs.Model
            BIOSVersion = $bios.SMBIOSBIOSVersion
            Domain = $cs.Domain
            InstanceId = if ($instanceId) { $instanceId } else { "Not EC2" }
            InstanceType = if ($instanceType) { $instanceType } else { "N/A" }
            AvailabilityZone = if ($availabilityZone) { $availabilityZone } else { "N/A" }
        }
        
        $script:DiagnosticData['SystemInfo'] = $sysInfo
        
        foreach ($key in $sysInfo.Keys | Sort-Object) {
            Write-ForensicsLog "$key : $($sysInfo[$key])" -Level Info
        }
        
        Write-ForensicsLog "System information collected successfully" -Level Success
        
    } catch {
        Write-ForensicsLog "Error collecting system information: $_" -Level Error
    }
}

#endregion

#region Performance Counters

Function Get-PerformanceCounters {
    Write-ForensicsHeader "PERFORMANCE COUNTER COLLECTION"
    
    Write-ForensicsLog "Resetting performance counters..." -Level Info
    try {
        Push-Location C:\Windows\System32
        lodctr /R | Out-Null
        Pop-Location
        
        Push-Location C:\Windows\SysWOW64
        lodctr /R | Out-Null
        Pop-Location
        
        winmgmt.exe /resyncperf | Out-Null
        
        Restart-Service -Name "pla" -Force -ErrorAction SilentlyContinue | Out-Null
        Restart-Service -Name "winmgmt" -Force -ErrorAction SilentlyContinue | Out-Null
        
        Write-ForensicsLog "Performance counters reset successfully" -Level Success
        Start-Sleep -Seconds 2
    } catch {
        Write-ForensicsLog "Warning: Failed to reset some counters: $_" -Level Warning
    }
    
    $counters = @(
        '\PhysicalDisk(*)\% Idle Time'
        '\PhysicalDisk(*)\Avg. Disk sec/Read'
        '\PhysicalDisk(*)\Avg. Disk sec/Write'
        '\PhysicalDisk(*)\Disk Reads/sec'
        '\PhysicalDisk(*)\Disk Writes/sec'
        '\PhysicalDisk(*)\Current Disk Queue Length'
        '\Processor(*)\% Processor Time'
        '\Processor(*)\% Privileged Time'
        '\Processor(*)\% User Time'
        '\Processor(*)\% Interrupt Time'
        '\Processor(*)\DPCs Queued/sec'
        '\System\Context Switches/sec'
        '\System\Processor Queue Length'
        '\Memory\Available Bytes'
        '\Memory\Pages/sec'
        '\Memory\Page Faults/sec'
        '\Memory\Pool Nonpaged Bytes'
        '\Memory\Pool Paged Bytes'
        '\Memory\Cache Bytes'
        '\Network Interface(*)\Bytes Total/sec'
        '\Network Interface(*)\Output Queue Length'
        '\Network Interface(*)\Packets Received Errors'
        '\TCPv4\Segments Retransmitted/sec'
    )
    
    Write-ForensicsLog "Collecting performance data (30 seconds)..." -Level Info
    
    $samples = @()
    $sampleInterval = if ($Mode -eq 'Quick') { 1 } elseif ($Mode -eq 'Deep') { 5 } else { 3 }
    $sampleCount = if ($Mode -eq 'Quick') { 3 } elseif ($Mode -eq 'Deep') { 10 } else { 5 }
    
    foreach ($counter in $counters) {
        try {
            $counterSamples = (Get-Counter -Counter $counter -SampleInterval $sampleInterval -MaxSamples $sampleCount -ErrorAction SilentlyContinue).CounterSamples
            foreach ($sample in $counterSamples) {
                $samples += [PSCustomObject]@{
                    Category = $sample.Path.Split('\')[3]
                    Counter = $sample.Path.Split('\')[4]
                    Instance = $sample.InstanceName
                    Value = [math]::Round($sample.CookedValue, 4)
                    Timestamp = $sample.Timestamp
                }
            }
        } catch {
            Write-ForensicsLog "Warning: Failed to collect counter $counter" -Level Warning
        }
    }
    
    $script:DiagnosticData['PerformanceCounters'] = $samples
    Write-ForensicsLog "Collected $($samples.Count) performance counter samples" -Level Success
    
    # Analyze performance counters
    Analyze-PerformanceCounters -Samples $samples
}

Function Analyze-PerformanceCounters {
    param($Samples)
    
    Write-ForensicsLog "`nAnalyzing performance data for bottlenecks..." -Level Info
    
    # Disk Analysis
    $diskReadLatency = ($Samples | Where-Object { $_.Counter -eq 'Avg. Disk sec/Read' -and $_.Instance -ne '_Total' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($diskReadLatency -gt 0.020) {
        Add-Bottleneck -Category "Disk" -Issue "High read latency" `
            -Value "$([math]::Round($diskReadLatency * 1000, 2))ms" -Threshold "20ms" -Impact "High"
    }
    
    $diskWriteLatency = ($Samples | Where-Object { $_.Counter -eq 'Avg. Disk sec/Write' -and $_.Instance -ne '_Total' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($diskWriteLatency -gt 0.020) {
        Add-Bottleneck -Category "Disk" -Issue "High write latency" `
            -Value "$([math]::Round($diskWriteLatency * 1000, 2))ms" -Threshold "20ms" -Impact "High"
    }
    
    $diskQueue = ($Samples | Where-Object { $_.Counter -eq 'Current Disk Queue Length' -and $_.Instance -ne '_Total' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($diskQueue -gt 2) {
        Add-Bottleneck -Category "Disk" -Issue "High disk queue length" `
            -Value "$([math]::Round($diskQueue, 2))" -Threshold "2" -Impact "High"
    }
    
    # CPU Analysis
    $cpuUsage = ($Samples | Where-Object { $_.Counter -eq '% Processor Time' -and $_.Instance -eq '_Total' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($cpuUsage -gt 80) {
        Add-Bottleneck -Category "CPU" -Issue "High CPU utilization" `
            -Value "$([math]::Round($cpuUsage, 2))%" -Threshold "80%" -Impact "High"
    }
    
    $contextSwitches = ($Samples | Where-Object { $_.Counter -eq 'Context Switches/sec' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($contextSwitches -gt 15000) {
        Add-Bottleneck -Category "CPU" -Issue "Excessive context switches" `
            -Value "$([math]::Round($contextSwitches, 0))/sec" -Threshold "15000/sec" -Impact "Medium"
    }
    
    $processorQueue = ($Samples | Where-Object { $_.Counter -eq 'Processor Queue Length' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($processorQueue -gt 2) {
        Add-Bottleneck -Category "CPU" -Issue "High processor queue length" `
            -Value "$([math]::Round($processorQueue, 2))" -Threshold "2" -Impact "High"
    }
    
    # Memory Analysis
    $totalMemory = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $availableMemory = ($Samples | Where-Object { $_.Counter -eq 'Available Bytes' } | 
        Measure-Object -Property Value -Average).Average
    $memoryPercentAvailable = ($availableMemory / $totalMemory) * 100
    
    if ($memoryPercentAvailable -lt 10) {
        Add-Bottleneck -Category "Memory" -Issue "Low available memory" `
            -Value "$([math]::Round($memoryPercentAvailable, 2))%" -Threshold "10%" -Impact "Critical"
    }
    
    $pagesPerSec = ($Samples | Where-Object { $_.Counter -eq 'Pages/sec' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($pagesPerSec -gt 10) {
        Add-Bottleneck -Category "Memory" -Issue "High memory paging" `
            -Value "$([math]::Round($pagesPerSec, 2))/sec" -Threshold "10/sec" -Impact "High"
    }
    
    $pageFaults = ($Samples | Where-Object { $_.Counter -eq 'Page Faults/sec' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($pageFaults -gt 1000) {
        Add-Bottleneck -Category "Memory" -Issue "High page fault rate" `
            -Value "$([math]::Round($pageFaults, 0))/sec" -Threshold "1000/sec" -Impact "Medium"
    }
    
    # Network Analysis
    $retransmits = ($Samples | Where-Object { $_.Counter -eq 'Segments Retransmitted/sec' } | 
        Measure-Object -Property Value -Average).Average
    
    if ($retransmits -gt 10) {
        Add-Bottleneck -Category "Network" -Issue "High TCP retransmissions" `
            -Value "$([math]::Round($retransmits, 2))/sec" -Threshold "10/sec" -Impact "Medium"
    }
}

#endregion

#region Disk Forensics

Function Test-DiskPerformance {
    Write-ForensicsHeader "DISK I/O PERFORMANCE TESTING"
    
    if ($Mode -eq 'CPUOnly' -or $Mode -eq 'MemoryOnly') {
        Write-ForensicsLog "Skipping disk tests in $Mode mode" -Level Info
        return
    }
    
    $testPath = Join-Path $env:TEMP "forensics-disk-test"
    $testFile = Join-Path $testPath "test.dat"
    
    try {
        # Create test directory
        New-Item -Path $testPath -ItemType Directory -Force | Out-Null
        
        # Create test file
        Write-ForensicsLog "Creating $($DiskTestSize)GB test file..." -Level Info
        $testFileSizeBytes = $DiskTestSize * 1GB
        
        & fsutil file createnew $testFile $testFileSizeBytes | Out-Null
        & fsutil file setvaliddata $testFile $testFileSizeBytes | Out-Null
        
        Write-ForensicsLog "Test file created successfully" -Level Success
        
        # Test parameters
        $blockSizes = if ($Mode -eq 'Quick') { @(4KB, 64KB) } 
                     elseif ($Mode -eq 'Deep') { @(4KB, 8KB, 64KB, 256KB, 1MB) }
                     else { @(4KB, 64KB, 256KB) }
        
        $results = @()
        
        foreach ($blockSize in $blockSizes) {
            Write-ForensicsLog "Testing with $($blockSize/1KB)KB block size..." -Level Info
            
            # Sequential Read Test
            $readTest = Measure-Command {
                $buffer = New-Object byte[] $blockSize
                $stream = [System.IO.File]::OpenRead($testFile)
                $bytesRead = 0
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $bytesRead += $read
                    if ($bytesRead -ge 100MB) { break }  # Read 100MB sample
                }
                $stream.Close()
            }
            
            $readThroughput = (100MB / $readTest.TotalSeconds) / 1MB
            $readIOPS = (100MB / $blockSize) / $readTest.TotalSeconds
            
            # Sequential Write Test
            $writeTest = Measure-Command {
                $buffer = New-Object byte[] $blockSize
                $stream = [System.IO.File]::OpenWrite($testFile)
                $bytesWritten = 0
                while ($bytesWritten -lt 100MB) {
                    $stream.Write($buffer, 0, $buffer.Length)
                    $bytesWritten += $buffer.Length
                }
                $stream.Flush()
                $stream.Close()
            }
            
            $writeThroughput = (100MB / $writeTest.TotalSeconds) / 1MB
            $writeIOPS = (100MB / $blockSize) / $writeTest.TotalSeconds
            
            $results += [PSCustomObject]@{
                BlockSizeKB = $blockSize / 1KB
                ReadMBps = [math]::Round($readThroughput, 2)
                ReadIOPS = [math]::Round($readIOPS, 0)
                ReadLatencyMs = [math]::Round(($readTest.TotalMilliseconds / ($readIOPS * $readTest.TotalSeconds)) * 1000, 2)
                WriteMBps = [math]::Round($writeThroughput, 2)
                WriteIOPS = [math]::Round($writeIOPS, 0)
                WriteLatencyMs = [math]::Round(($writeTest.TotalMilliseconds / ($writeIOPS * $writeTest.TotalSeconds)) * 1000, 2)
            }
            
            Write-ForensicsLog "  Read: $([math]::Round($readThroughput, 2)) MB/s, $([math]::Round($readIOPS, 0)) IOPS" -Level Info
            Write-ForensicsLog "  Write: $([math]::Round($writeThroughput, 2)) MB/s, $([math]::Round($writeIOPS, 0)) IOPS" -Level Info
        }
        
        $script:DiagnosticData['DiskPerformance'] = $results
        
        # Analyze disk performance
        $avgReadLatency = ($results | Measure-Object -Property ReadLatencyMs -Average).Average
        $avgWriteLatency = ($results | Measure-Object -Property WriteLatencyMs -Average).Average
        
        if ($avgReadLatency -gt 20) {
            Add-Bottleneck -Category "Disk" -Issue "Poor read performance in I/O test" `
                -Value "$([math]::Round($avgReadLatency, 2))ms" -Threshold "20ms" -Impact "High"
        }
        
        if ($avgWriteLatency -gt 20) {
            Add-Bottleneck -Category "Disk" -Issue "Poor write performance in I/O test" `
                -Value "$([math]::Round($avgWriteLatency, 2))ms" -Threshold "20ms" -Impact "High"
        }
        
        Write-ForensicsLog "Disk performance testing completed" -Level Success
        
    } catch {
        Write-ForensicsLog "Error during disk testing: $_" -Level Error
    } finally {
        # Cleanup
        if (Test-Path $testFile) {
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $testPath) {
            Remove-Item $testPath -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion

#region CPU Forensics

Function Get-CPUForensics {
    Write-ForensicsHeader "CPU FORENSICS"
    
    if ($Mode -eq 'DiskOnly' -or $Mode -eq 'MemoryOnly') {
        Write-ForensicsLog "Skipping CPU forensics in $Mode mode" -Level Info
        return
    }
    
    try {
        # Get CPU information
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        
        Write-ForensicsLog "CPU: $($cpu.Name)" -Level Info
        Write-ForensicsLog "Cores: $($cpu.NumberOfCores), Logical Processors: $($cpu.NumberOfLogicalProcessors)" -Level Info
        Write-ForensicsLog "Current Clock Speed: $($cpu.CurrentClockSpeed) MHz" -Level Info
        Write-ForensicsLog "Max Clock Speed: $($cpu.MaxClockSpeed) MHz" -Level Info
        
        # Get top CPU consumers
        Write-ForensicsLog "`nTop 10 CPU-consuming processes:" -Level Info
        $topProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 | 
            Select-Object ProcessName, Id, CPU, WorkingSet, Threads
        
        foreach ($proc in $topProcesses) {
            $cpuTime = [math]::Round($proc.CPU, 2)
            $memoryMB = [math]::Round($proc.WorkingSet / 1MB, 2)
            Write-ForensicsLog "  $($proc.ProcessName) (PID: $($proc.Id)) - CPU: $cpuTime s, Memory: $memoryMB MB, Threads: $($proc.Threads.Count)" -Level Info
        }
        
        # Check for CPU throttling
        $currentSpeed = $cpu.CurrentClockSpeed
        $maxSpeed = $cpu.MaxClockSpeed
        $throttlePercent = (($maxSpeed - $currentSpeed) / $maxSpeed) * 100
        
        if ($throttlePercent -gt 10) {
            Add-Bottleneck -Category "CPU" -Issue "CPU throttling detected" `
                -Value "$([math]::Round($throttlePercent, 2))% below max" -Threshold "10%" -Impact "Medium"
        }
        
        # Get thread count
        $totalThreads = (Get-Process | Measure-Object -Property Threads -Sum).Sum
        Write-ForensicsLog "`nTotal system threads: $totalThreads" -Level Info
        
        if ($totalThreads -gt 2000) {
            Add-Bottleneck -Category "CPU" -Issue "Excessive thread count" `
                -Value "$totalThreads" -Threshold "2000" -Impact "Medium"
        }
        
        # Check for processes with excessive threads
        $threadHogs = Get-Process | Where-Object { $_.Threads.Count -gt 100 } | 
            Sort-Object { $_.Threads.Count } -Descending | Select-Object -First 5
        
        if ($threadHogs) {
            Write-ForensicsLog "`nProcesses with excessive threads:" -Level Warning
            foreach ($proc in $threadHogs) {
                Write-ForensicsLog "  $($proc.ProcessName) (PID: $($proc.Id)) - $($proc.Threads.Count) threads" -Level Warning
            }
        }
        
        $script:DiagnosticData['CPUForensics'] = @{
            CPUInfo = $cpu
            TopProcesses = $topProcesses
            TotalThreads = $totalThreads
            ThrottlePercent = $throttlePercent
        }
        
        Write-ForensicsLog "`nCPU forensics completed" -Level Success
        
    } catch {
        Write-ForensicsLog "Error during CPU forensics: $_" -Level Error
    }
}

#endregion

#region Memory Forensics

Function Get-MemoryForensics {
    Write-ForensicsHeader "MEMORY FORENSICS"
    
    if ($Mode -eq 'DiskOnly' -or $Mode -eq 'CPUOnly') {
        Write-ForensicsLog "Skipping memory forensics in $Mode mode" -Level Info
        return
    }
    
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        
        $totalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemoryGB = $totalMemoryGB - $freeMemoryGB
        $memoryUsagePercent = ($usedMemoryGB / $totalMemoryGB) * 100
        
        Write-ForensicsLog "Total Memory: $totalMemoryGB GB" -Level Info
        Write-ForensicsLog "Used Memory: $usedMemoryGB GB ($([math]::Round($memoryUsagePercent, 2))%)" -Level Info
        Write-ForensicsLog "Free Memory: $freeMemoryGB GB" -Level Info
        
        # Get top memory consumers
        Write-ForensicsLog "`nTop 10 memory-consuming processes:" -Level Info
        $topMemoryProcesses = Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 10 | 
            Select-Object ProcessName, Id, WorkingSet, PrivateMemorySize, VirtualMemorySize
        
        foreach ($proc in $topMemoryProcesses) {
            $wsMB = [math]::Round($proc.WorkingSet / 1MB, 2)
            $privateMB = [math]::Round($proc.PrivateMemorySize / 1MB, 2)
            $virtualMB = [math]::Round($proc.VirtualMemorySize / 1MB, 2)
            Write-ForensicsLog "  $($proc.ProcessName) (PID: $($proc.Id)) - WS: $wsMB MB, Private: $privateMB MB, Virtual: $virtualMB MB" -Level Info
        }
        
        # Check for memory leaks (processes with high virtual memory)
        $potentialLeaks = Get-Process | Where-Object { 
            $_.VirtualMemorySize -gt 2GB -and $_.WorkingSet -lt ($_.VirtualMemorySize * 0.3)
        } | Select-Object -First 5
        
        if ($potentialLeaks) {
            Write-ForensicsLog "`nPotential memory leaks detected:" -Level Warning
            foreach ($proc in $potentialLeaks) {
                $virtualGB = [math]::Round($proc.VirtualMemorySize / 1GB, 2)
                $wsGB = [math]::Round($proc.WorkingSet / 1GB, 2)
                Write-ForensicsLog "  $($proc.ProcessName) (PID: $($proc.Id)) - Virtual: $virtualGB GB, Working Set: $wsGB GB" -Level Warning
                
                Add-Bottleneck -Category "Memory" -Issue "Potential memory leak in $($proc.ProcessName)" `
                    -Value "$virtualGB GB virtual" -Threshold "2 GB" -Impact "Medium"
            }
        }
        
        # Get page file information
        $pageFiles = Get-CimInstance Win32_PageFileUsage
        if ($pageFiles) {
            Write-ForensicsLog "`nPage File Usage:" -Level Info
            foreach ($pf in $pageFiles) {
                $usagePercent = ($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100
                Write-ForensicsLog "  $($pf.Name) - $($pf.CurrentUsage) MB / $($pf.AllocatedBaseSize) MB ($([math]::Round($usagePercent, 2))%)" -Level Info
                
                if ($usagePercent -gt 80) {
                    Add-Bottleneck -Category "Memory" -Issue "High page file usage" `
                        -Value "$([math]::Round($usagePercent, 2))%" -Threshold "80%" -Impact "High"
                }
            }
        }
        
        # Check committed memory
        $committedBytes = $os.TotalVirtualMemorySize * 1KB
        $committedLimit = $os.TotalVisibleMemorySize * 1KB + ($pageFiles | Measure-Object -Property AllocatedBaseSize -Sum).Sum * 1MB
        $commitPercent = ($committedBytes / $committedLimit) * 100
        
        Write-ForensicsLog "`nCommitted Memory: $([math]::Round($committedBytes / 1GB, 2)) GB / $([math]::Round($committedLimit / 1GB, 2)) GB ($([math]::Round($commitPercent, 2))%)" -Level Info
        
        if ($commitPercent -gt 90) {
            Add-Bottleneck -Category "Memory" -Issue "High committed memory" `
                -Value "$([math]::Round($commitPercent, 2))%" -Threshold "90%" -Impact "Critical"
        }
        
        $script:DiagnosticData['MemoryForensics'] = @{
            TotalMemoryGB = $totalMemoryGB
            UsedMemoryGB = $usedMemoryGB
            FreeMemoryGB = $freeMemoryGB
            MemoryUsagePercent = $memoryUsagePercent
            TopProcesses = $topMemoryProcesses
            PageFiles = $pageFiles
            CommitPercent = $commitPercent
        }
        
        Write-ForensicsLog "`nMemory forensics completed" -Level Success
        
    } catch {
        Write-ForensicsLog "Error during memory forensics: $_" -Level Error
    }
}

#endregion

#region AWS Support Integration

Function New-AWSSupportCase {
    Write-ForensicsHeader "AWS SUPPORT CASE CREATION"
    
    if ($script:Bottlenecks.Count -eq 0) {
        Write-ForensicsLog "No bottlenecks detected - skipping support case creation" -Level Info
        return
    }
    
    # Check AWS CLI
    try {
        $awsVersion = aws --version 2>&1
        Write-ForensicsLog "AWS CLI detected: $awsVersion" -Level Success
    } catch {
        Write-ForensicsLog "AWS CLI not found. Install from: https://aws.amazon.com/cli/" -Level Error
        return
    }
    
    # Build case description
    $sysInfo = $script:DiagnosticData['SystemInfo']
    
    $caseSubject = "Windows Performance Issues Detected - $($sysInfo.ComputerName)"
    
    $bottleneckSummary = $script:Bottlenecks | ForEach-Object {
        "[$($_.Impact)] $($_.Category): $($_.Issue) (Current: $($_.CurrentValue), Threshold: $($_.Threshold))"
    } | Out-String
    
    $caseDescription = @"
🐉 AUTOMATED WINDOWS FORENSICS REPORT 🐉

EXECUTIVE SUMMARY:
Comprehensive diagnostics detected $($script:Bottlenecks.Count) performance issue(s) requiring attention.

BOTTLENECKS DETECTED:
$bottleneckSummary

SYSTEM INFORMATION:
- Computer Name: $($sysInfo.ComputerName)
- OS: $($sysInfo.OSName) $($sysInfo.OSVersion) (Build $($sysInfo.OSBuild))
- Architecture: $($sysInfo.OSArchitecture)
- Uptime: $($sysInfo.Uptime.Days) days, $($sysInfo.Uptime.Hours) hours
- Total Memory: $($sysInfo.TotalMemoryGB) GB
- CPU: $($sysInfo.CPUName)
- CPU Cores: $($sysInfo.CPUCores) (Logical: $($sysInfo.CPULogicalProcessors))
- Manufacturer: $($sysInfo.Manufacturer) $($sysInfo.Model)
- Domain: $($sysInfo.Domain)
- Instance ID: $($sysInfo.InstanceId)
- Instance Type: $($sysInfo.InstanceType)
- Availability Zone: $($sysInfo.AvailabilityZone)

DIAGNOSTIC MODE: $Mode
TIMESTAMP: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")

Detailed forensics data is attached in the diagnostic report file.

Generated by: Invoke-WindowsForensics.ps1 v2.0
"@

    Write-ForensicsLog "Creating support case with severity: $Severity" -Level Info
    
    $caseJson = @{
        subject = $caseSubject
        serviceCode = "amazon-ec2-windows"
        severityCode = $Severity
        categoryCode = "performance"
        communicationBody = $caseDescription
        language = "en"
        issueType = "technical"
    } | ConvertTo-Json -Depth 10
    
    try {
        # Create the case
        $caseResult = aws support create-case --cli-input-json $caseJson 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $caseId = ($caseResult | ConvertFrom-Json).caseId
            Write-ForensicsLog "Support case created successfully!" -Level Success
            Write-ForensicsLog "Case ID: $caseId" -Level Success
            
            # Attach diagnostic file
            Write-ForensicsLog "Attaching diagnostic report..." -Level Info
            
            if (Test-Path $script:OutputFile) {
                $attachmentContent = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:OutputFile))
                
                $attachmentJson = @{
                    attachments = @(
                        @{
                            fileName = Split-Path $script:OutputFile -Leaf
                            data = $attachmentContent
                        }
                    )
                } | ConvertTo-Json -Depth 10
                
                $attachmentSet = aws support add-attachments-to-set --cli-input-json $attachmentJson 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    $attachmentSetId = ($attachmentSet | ConvertFrom-Json).attachmentSetId
                    
                    aws support add-communication-to-case --case-id $caseId `
                        --communication-body "Complete forensics diagnostic report attached." `
                        --attachment-set-id $attachmentSetId | Out-Null
                    
                    Write-ForensicsLog "Diagnostic report attached successfully" -Level Success
                }
            }
            
            Write-ForensicsLog "`nView your case: https://console.aws.amazon.com/support/home#/case/?displayId=$caseId" -Level Info
            
            return $caseId
            
        } else {
            Write-ForensicsLog "Failed to create support case: $caseResult" -Level Error
        }
        
    } catch {
        Write-ForensicsLog "Error creating support case: $_" -Level Error
        Write-ForensicsLog "Ensure you have:" -Level Info
        Write-ForensicsLog "  1. AWS CLI configured (aws configure)" -Level Info
        Write-ForensicsLog "  2. Active AWS Support plan (Business or Enterprise)" -Level Info
        Write-ForensicsLog "  3. IAM permissions for support:CreateCase" -Level Info
    }
}

#endregion

#region Main Execution

Function Invoke-Forensics {
    $startTime = Get-Date
    
    # Banner
    Write-Host "`n" -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                                               ║" -ForegroundColor Cyan
    Write-Host "║              🐉 WINDOWS PERFORMANCE FORENSICS TOOL v2.0 🐉                   ║" -ForegroundColor Cyan
    Write-Host "║                                                                               ║" -ForegroundColor Cyan
    Write-Host "║                    Comprehensive System Diagnostics                           ║" -ForegroundColor Cyan
    Write-Host "║                    with AWS Support Integration                               ║" -ForegroundColor Cyan
    Write-Host "║                                                                               ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "`n"
    
    Write-ForensicsLog "Starting forensics analysis in $Mode mode..." -Level Info
    Write-ForensicsLog "Output file: $script:OutputFile" -Level Info
    Write-Host "`n"
    
    # Execute diagnostics based on mode
    Get-SystemInformation
    
    switch ($Mode) {
        'Quick' {
            Get-PerformanceCounters
        }
        'Standard' {
            Get-PerformanceCounters
            Test-DiskPerformance
            Get-CPUForensics
            Get-MemoryForensics
        }
        'Deep' {
            Get-PerformanceCounters
            Test-DiskPerformance
            Get-CPUForensics
            Get-MemoryForensics
        }
        'DiskOnly' {
            Get-PerformanceCounters
            Test-DiskPerformance
        }
        'CPUOnly' {
            Get-PerformanceCounters
            Get-CPUForensics
        }
        'MemoryOnly' {
            Get-PerformanceCounters
            Get-MemoryForensics
        }
    }
    
    # Summary
    Write-ForensicsHeader "FORENSICS SUMMARY"
    
    $duration = (Get-Date) - $startTime
    Write-ForensicsLog "Analysis completed in $([math]::Round($duration.TotalSeconds, 2)) seconds" -Level Success
    
    if ($script:Bottlenecks.Count -eq 0) {
        Write-Host "`n✅ " -NoNewline -ForegroundColor Green
        Write-Host "NO DRAGONS FOUND! System performance looks healthy." -ForegroundColor Green
    } else {
        Write-Host "`n🐉 " -NoNewline -ForegroundColor Magenta
        Write-Host "DRAGONS DETECTED: $($script:Bottlenecks.Count) performance issue(s) found" -ForegroundColor Magenta
        Write-Host "`n"
        
        # Group by impact
        $critical = $script:Bottlenecks | Where-Object { $_.Impact -eq 'Critical' }
        $high = $script:Bottlenecks | Where-Object { $_.Impact -eq 'High' }
        $medium = $script:Bottlenecks | Where-Object { $_.Impact -eq 'Medium' }
        $low = $script:Bottlenecks | Where-Object { $_.Impact -eq 'Low' }
        
        if ($critical) {
            Write-Host "  CRITICAL ISSUES ($($critical.Count)):" -ForegroundColor Red
            foreach ($issue in $critical) {
                Write-Host "    • $($issue.Category): $($issue.Issue)" -ForegroundColor Red
            }
        }
        
        if ($high) {
            Write-Host "  HIGH PRIORITY ($($high.Count)):" -ForegroundColor Yellow
            foreach ($issue in $high) {
                Write-Host "    • $($issue.Category): $($issue.Issue)" -ForegroundColor Yellow
            }
        }
        
        if ($medium) {
            Write-Host "  MEDIUM PRIORITY ($($medium.Count)):" -ForegroundColor Yellow
            foreach ($issue in $medium) {
                Write-Host "    • $($issue.Category): $($issue.Issue)" -ForegroundColor Yellow
            }
        }
        
        if ($low) {
            Write-Host "  LOW PRIORITY ($($low.Count)):" -ForegroundColor Gray
            foreach ($issue in $low) {
                Write-Host "    • $($issue.Category): $($issue.Issue)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host "`n"
    Write-ForensicsLog "Detailed report saved to: $script:OutputFile" -Level Info
    
    # Create AWS Support case if requested
    if ($CreateSupportCase -and $script:Bottlenecks.Count -gt 0) {
        Write-Host "`n"
        $caseId = New-AWSSupportCase
        if ($caseId) {
            Write-Host "`n✅ AWS Support case created: $caseId" -ForegroundColor Green
        }
    } elseif ($script:Bottlenecks.Count -gt 0 -and -not $CreateSupportCase) {
        Write-Host "`n💡 Tip: Run with -CreateSupportCase to automatically open an AWS Support case" -ForegroundColor Cyan
    }
    
    Write-Host "`n"
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                         Forensics Analysis Complete                            " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "`n"
}

# Execute main function
Invoke-Forensics

#endregion
