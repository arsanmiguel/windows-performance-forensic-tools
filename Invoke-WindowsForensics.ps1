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
    
    Write-ForensicsLog "BOTTLENECK FOUND: $Category - $Issue (Current: $Value, Threshold: $Threshold)" -Level Dragon
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

#region Storage Profiling

Function Get-StorageProfile {
    Write-ForensicsHeader "STORAGE PROFILING"
    
    Write-ForensicsLog "Performing comprehensive storage analysis..." -Level Info
    
    try {
        # ==========================================================================
        # STORAGE TOPOLOGY
        # ==========================================================================
        Write-ForensicsLog "`n--- STORAGE TOPOLOGY ---" -Level Info
        
        # Physical disks
        Write-ForensicsLog "`nPhysical Disks:" -Level Info
        $physicalDisks = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, Size, HealthStatus, OperationalStatus
        foreach ($disk in $physicalDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            Write-ForensicsLog "  $($disk.FriendlyName): $($disk.MediaType), $($disk.BusType), ${sizeGB}GB, Health: $($disk.HealthStatus)" -Level Info
        }
        
        # Disks and Partition Schemes
        Write-ForensicsLog "`nDisk Partition Schemes:" -Level Info
        
        $mbrCount = 0
        $gptCount = 0
        $rawCount = 0
        
        Get-Disk | ForEach-Object {
            $disk = $_
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            $partStyle = $disk.PartitionStyle
            $bootType = if ($disk.IsBoot) { "Boot" } else { "" }
            $systemType = if ($disk.IsSystem) { "System" } else { "" }
            $busType = $disk.BusType
            $diskStatus = $disk.OperationalStatus
            $healthStatus = $disk.HealthStatus
            
            # Count partition styles
            switch ($partStyle) {
                "MBR" { $mbrCount++ }
                "GPT" { $gptCount++ }
                "RAW" { $rawCount++ }
            }
            
            Write-ForensicsLog "  Disk $($disk.Number): $($disk.FriendlyName)" -Level Info
            Write-ForensicsLog "    Size: ${sizeGB}GB | Partition Style: $partStyle | Bus: $busType" -Level Info
            Write-ForensicsLog "    Status: $diskStatus | Health: $healthStatus | $bootType $systemType" -Level Info
            
            # Warn about MBR on large disks (>2TB limit)
            if ($partStyle -eq "MBR" -and $disk.Size -gt 2TB) {
                Write-ForensicsLog "    WARNING: MBR partition style on disk >2TB - only 2TB usable!" -Level Warning
                Add-Bottleneck -Category "Storage" -Issue "MBR partition on disk >2TB (data loss risk)" `
                    -Value "MBR on ${sizeGB}GB disk" -Threshold "GPT" -Impact "High"
            }
            
            # Warn about RAW disks
            if ($partStyle -eq "RAW") {
                Write-ForensicsLog "    WARNING: Disk is RAW (uninitialized)" -Level Warning
            }
            
            # Check disk health
            if ($healthStatus -ne "Healthy") {
                Add-Bottleneck -Category "Storage" -Issue "Disk $($disk.Number) health issue" `
                    -Value "$healthStatus" -Threshold "Healthy" -Impact "Critical"
            }
            
            # Get detailed partition information
            Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | ForEach-Object {
                $partition = $_
                $partSizeGB = [math]::Round($partition.Size / 1GB, 2)
                $partType = $partition.Type
                $partGuid = $partition.GptType
                
                # Translate partition type
                $partTypeName = switch ($partType) {
                    "System" { "EFI System Partition (ESP)" }
                    "Reserved" { "Microsoft Reserved (MSR)" }
                    "Basic" { "Basic Data" }
                    "Recovery" { "Windows Recovery" }
                    "Unknown" { 
                        # Check GPT GUID for more detail
                        switch ($partGuid) {
                            "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" { "Microsoft Reserved (MSR)" }
                            "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" { "Basic Data" }
                            "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" { "EFI System Partition" }
                            "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" { "Windows Recovery" }
                            "{e75caf8f-f680-4cee-afa3-b001e56efc2d}" { "Storage Spaces" }
                            "{5808c8aa-7e8f-42e0-85d2-e1e90434cfb3}" { "LDM Metadata" }
                            "{af9b60a0-1431-4f62-bc68-3311714a69ad}" { "LDM Data" }
                            "{db97dba9-0840-4bae-97f0-ffb9a327c7e1}" { "Windows RE Tools" }
                            default { "Unknown ($partGuid)" }
                        }
                    }
                    default { $partType }
                }
                
                $volume = Get-Volume -Partition $partition -ErrorAction SilentlyContinue
                if ($volume -and $volume.DriveLetter) {
                    Write-ForensicsLog "    Partition $($partition.PartitionNumber): $($volume.DriveLetter): - $partTypeName - $($volume.FileSystem) - ${partSizeGB}GB" -Level Info
                } else {
                    Write-ForensicsLog "    Partition $($partition.PartitionNumber): (No letter) - $partTypeName - ${partSizeGB}GB" -Level Info
                }
            }
            Write-ForensicsLog "" -Level Info
        }
        
        # Partition scheme summary
        Write-ForensicsLog "Partition Scheme Summary:" -Level Info
        Write-ForensicsLog "  GPT Disks: $gptCount (modern, UEFI compatible, >2TB support)" -Level Info
        Write-ForensicsLog "  MBR Disks: $mbrCount (legacy, BIOS, 2TB max)" -Level Info
        if ($rawCount -gt 0) {
            Write-ForensicsLog "  RAW Disks: $rawCount (uninitialized)" -Level Warning
        }
        
        # Check boot mode (UEFI vs Legacy BIOS)
        Write-ForensicsLog "`nBoot Configuration:" -Level Info
        try {
            $firmware = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction SilentlyContinue)
            if ($firmware) {
                $secureBoot = if ($firmware.UEFISecureBootEnabled -eq 1) { "Enabled" } else { "Disabled" }
                Write-ForensicsLog "  Firmware: UEFI (Secure Boot: $secureBoot)" -Level Info
            } else {
                # Check alternative method
                $env:firmware_type = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -ErrorAction SilentlyContinue).SystemBiosVersion
                if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot") {
                    Write-ForensicsLog "  Firmware: UEFI" -Level Info
                } else {
                    Write-ForensicsLog "  Firmware: Legacy BIOS" -Level Info
                }
            }
        } catch {
            # Fallback detection using bcdedit
            try {
                $bcdedit = bcdedit /enum firmware 2>&1
                if ($bcdedit -match "Windows Boot Manager") {
                    Write-ForensicsLog "  Firmware: UEFI" -Level Info
                } else {
                    Write-ForensicsLog "  Firmware: Legacy BIOS (or unable to determine)" -Level Info
                }
            } catch {
                Write-ForensicsLog "  Firmware: Unable to determine" -Level Warning
            }
        }
        
        # ReFS detection (modern Windows Server filesystem)
        Write-ForensicsLog "`nFilesystem Types:" -Level Info
        $filesystems = Get-Volume | Where-Object { $_.DriveType -eq "Fixed" } | Group-Object FileSystem
        foreach ($fs in $filesystems) {
            $fsName = if ($fs.Name) { $fs.Name } else { "Unknown" }
            Write-ForensicsLog "  $fsName : $($fs.Count) volume(s)" -Level Info
            
            # Note about ReFS
            if ($fsName -eq "ReFS") {
                Write-ForensicsLog "    ReFS detected - Resilient File System (integrity streams, auto-repair)" -Level Info
            }
        }
        
        # Dev Drive detection (Windows 11 22H2+ / Server 2025)
        try {
            $devDrives = Get-Volume | Where-Object { $_.FileSystemType -eq "ReFS" -and $_.AllocationUnitSize -eq 65536 }
            if ($devDrives) {
                Write-ForensicsLog "`nDev Drives (Performance Mode Volumes):" -Level Info
                foreach ($dd in $devDrives) {
                    Write-ForensicsLog "  $($dd.DriveLetter): - Dev Drive (ReFS with 64K allocation)" -Level Info
                }
            }
        } catch {
            # Dev Drive detection not available on older Windows
        }
        
        # Storage Spaces detection
        Write-ForensicsLog "`nStorage Spaces:" -Level Info
        $storagePools = Get-StoragePool -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -ne "Primordial" }
        if ($storagePools) {
            foreach ($pool in $storagePools) {
                Write-ForensicsLog "  Pool: $($pool.FriendlyName) - Health: $($pool.HealthStatus) - Size: $([math]::Round($pool.Size / 1GB, 2))GB" -Level Info
                
                Get-VirtualDisk -StoragePool $pool -ErrorAction SilentlyContinue | ForEach-Object {
                    Write-ForensicsLog "    Virtual Disk: $($_.FriendlyName) - $($_.ResiliencySettingName) - Health: $($_.HealthStatus)" -Level Info
                }
            }
        } else {
            Write-ForensicsLog "  No Storage Spaces configured" -Level Info
        }
        
        # Dynamic Disks Detection and Analysis
        Write-ForensicsLog "`nDynamic Disks:" -Level Info
        
        # Check for dynamic disks using WMI
        $dynamicDisksWmi = Get-WmiObject -Class Win32_DiskPartition -ErrorAction SilentlyContinue | 
            Where-Object { $_.Type -like "*Logical Disk Manager*" }
        
        if ($dynamicDisksWmi) {
            Write-ForensicsLog "  Dynamic disk configuration detected" -Level Info
            
            # Get dynamic volumes (mirrored, striped, spanned, RAID-5)
            $ldmVolumes = Get-WmiObject -Class Win32_Volume -ErrorAction SilentlyContinue | 
                Where-Object { $_.DriveType -eq 3 }
            
            foreach ($vol in $ldmVolumes) {
                if ($vol.DriveLetter) {
                    $volSizeGB = [math]::Round($vol.Capacity / 1GB, 2)
                    $volFreeGB = [math]::Round($vol.FreeSpace / 1GB, 2)
                    Write-ForensicsLog "  Volume $($vol.DriveLetter) - $($vol.FileSystem) - ${volSizeGB}GB (${volFreeGB}GB free)" -Level Info
                }
            }
            
            # Use diskpart to get detailed dynamic disk info
            Write-ForensicsLog "`n  Dynamic Volume Details (via diskpart):" -Level Info
            try {
                $diskpartScript = @"
list volume
"@
                $diskpartOutput = $diskpartScript | diskpart 2>&1
                $diskpartOutput | Where-Object { $_ -match "Mirror|Stripe|Span|RAID" } | ForEach-Object {
                    Write-ForensicsLog "    $_" -Level Info
                }
                
                # Check for degraded/failed volumes
                $degradedVolumes = $diskpartOutput | Where-Object { $_ -match "Failed|Degraded|At Risk|Unknown" }
                if ($degradedVolumes) {
                    Write-ForensicsLog "`n  WARNING: Degraded/Failed dynamic volumes detected:" -Level Warning
                    $degradedVolumes | ForEach-Object {
                        Write-ForensicsLog "    $_" -Level Warning
                    }
                    Add-Bottleneck -Category "Storage" -Issue "Degraded dynamic disk volume detected" `
                        -Value "Degraded/Failed" -Threshold "Healthy" -Impact "Critical"
                }
            } catch {
                Write-ForensicsLog "    Unable to query diskpart: $_" -Level Warning
            }
            
            # Check dynamic disk health via WMI
            Write-ForensicsLog "`n  Dynamic Disk Health:" -Level Info
            Get-WmiObject -Class Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
                $disk = $_
                $status = $disk.Status
                $mediaType = $disk.MediaType
                
                Write-ForensicsLog "    $($disk.DeviceID): Status=$status, MediaType=$mediaType" -Level Info
                
                if ($status -ne "OK" -and $status -ne $null) {
                    Add-Bottleneck -Category "Storage" -Issue "Dynamic disk health issue on $($disk.DeviceID)" `
                        -Value "$status" -Threshold "OK" -Impact "High"
                }
            }
            
        } else {
            Write-ForensicsLog "  No dynamic disk configuration detected (using Basic disks)" -Level Info
        }
        
        # Software RAID via Storage Spaces (modern alternative to dynamic disks)
        Write-ForensicsLog "`nSoftware RAID / Mirrored Volumes:" -Level Info
        
        # Check for mirrored volumes using vssadmin (works for both dynamic and Storage Spaces)
        try {
            $vssOutput = vssadmin list volumes 2>&1
            $mirroredInfo = $vssOutput | Where-Object { $_ -match "Mirror|RAID|Parity" }
            if ($mirroredInfo) {
                Write-ForensicsLog "  Mirrored/RAID volumes found:" -Level Info
                $mirroredInfo | ForEach-Object { Write-ForensicsLog "    $_" -Level Info }
            } else {
                Write-ForensicsLog "  No mirrored/RAID volumes detected" -Level Info
            }
        } catch {
            Write-ForensicsLog "  Unable to query volume shadow copy service" -Level Warning
        }
        
        # ==========================================================================
        # STORAGE TIERING (SSD vs HDD vs NVMe)
        # ==========================================================================
        Write-ForensicsLog "`n--- STORAGE TIERING ---" -Level Info
        
        $ssdCount = 0
        $hddCount = 0
        $nvmeCount = 0
        $unknownCount = 0
        
        Write-ForensicsLog "`nDrive Types:" -Level Info
        foreach ($disk in $physicalDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            
            switch ($disk.MediaType) {
                "SSD" {
                    if ($disk.BusType -eq "NVMe") {
                        Write-ForensicsLog "  $($disk.FriendlyName): NVMe SSD - ${sizeGB}GB" -Level Info
                        $nvmeCount++
                    } else {
                        Write-ForensicsLog "  $($disk.FriendlyName): SATA SSD - ${sizeGB}GB" -Level Info
                        $ssdCount++
                    }
                }
                "HDD" {
                    Write-ForensicsLog "  $($disk.FriendlyName): HDD (Rotational) - ${sizeGB}GB" -Level Info
                    $hddCount++
                }
                default {
                    Write-ForensicsLog "  $($disk.FriendlyName): Unknown Type - ${sizeGB}GB" -Level Info
                    $unknownCount++
                }
            }
        }
        
        Write-ForensicsLog "`nStorage Tier Summary: NVMe=$nvmeCount, SSD=$ssdCount, HDD=$hddCount, Unknown=$unknownCount" -Level Info
        
        # Storage tiering recommendations
        if ($hddCount -gt 0 -and $ssdCount -eq 0 -and $nvmeCount -eq 0) {
            Write-ForensicsLog "  Recommendation: Consider adding SSD/NVMe for improved performance" -Level Warning
        }
        
        # ==========================================================================
        # AWS EBS / CLOUD STORAGE DETECTION
        # ==========================================================================
        Write-ForensicsLog "`n--- CLOUD STORAGE DETECTION ---" -Level Info
        
        # Check if running on EC2
        $instanceId = $null
        try {
            $instanceId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" -TimeoutSec 2 -ErrorAction SilentlyContinue
        } catch {
            # Not on AWS
        }
        
        if ($instanceId) {
            Write-ForensicsLog "`nAWS EC2 Instance Detected - Analyzing EBS Volumes:" -Level Info
            
            $region = $null
            try {
                $az = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/placement/availability-zone" -TimeoutSec 2
                $region = $az -replace '[a-z]$', ''
            } catch {}
            
            Write-ForensicsLog "  Instance ID: $instanceId" -Level Info
            Write-ForensicsLog "  Region: $region" -Level Info
            
            # Try AWS CLI for EBS details
            try {
                $awsCheck = Get-Command aws -ErrorAction SilentlyContinue
                if ($awsCheck) {
                    Write-ForensicsLog "`n  EBS Volumes (via AWS CLI):" -Level Info
                    
                    $ebsJson = aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=$instanceId" `
                        --query 'Volumes[*].{ID:VolumeId,Type:VolumeType,Size:Size,IOPS:Iops,Throughput:Throughput,State:State,Device:Attachments[0].Device}' `
                        --output json --region $region 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        $ebsVolumes = $ebsJson | ConvertFrom-Json
                        foreach ($vol in $ebsVolumes) {
                            Write-ForensicsLog "    $($vol.ID): $($vol.Type), $($vol.Size)GB, IOPS: $($vol.IOPS), Device: $($vol.Device)" -Level Info
                        }
                        
                        # Check for optimization opportunities
                        Write-ForensicsLog "`n  EBS Optimization Analysis:" -Level Info
                        
                        $gp2Count = ($ebsVolumes | Where-Object { $_.Type -eq "gp2" }).Count
                        if ($gp2Count -gt 0) {
                            Write-ForensicsLog "    - Found $gp2Count gp2 volume(s) - consider upgrading to gp3 for cost savings" -Level Warning
                            Add-Bottleneck -Category "Storage" -Issue "gp2 volumes detected - gp3 recommended" `
                                -Value "$gp2Count gp2 volumes" -Threshold "gp3" -Impact "Low"
                        }
                        
                        $io1Count = ($ebsVolumes | Where-Object { $_.Type -eq "io1" }).Count
                        if ($io1Count -gt 0) {
                            Write-ForensicsLog "    - Found $io1Count io1 volume(s) - consider upgrading to io2 for better durability" -Level Info
                        }
                    }
                } else {
                    Write-ForensicsLog "  AWS CLI not available for detailed EBS analysis" -Level Warning
                }
            } catch {
                Write-ForensicsLog "  Unable to query EBS volumes: $_" -Level Warning
            }
            
            # Check EBS-optimized status
            try {
                $ebsOptimized = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/ebs-optimized" -TimeoutSec 2 -ErrorAction SilentlyContinue
                Write-ForensicsLog "  EBS Optimized: $ebsOptimized" -Level Info
            } catch {}
            
        } else {
            Write-ForensicsLog "  Not running on AWS EC2" -Level Info
            
            # Check for Azure
            try {
                $azureMetadata = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" `
                    -Headers @{"Metadata"="true"} -TimeoutSec 2 -ErrorAction SilentlyContinue
                if ($azureMetadata) {
                    Write-ForensicsLog "`nAzure VM Detected:" -Level Info
                    Write-ForensicsLog "  VM Size: $($azureMetadata.compute.vmSize)" -Level Info
                    Write-ForensicsLog "  Location: $($azureMetadata.compute.location)" -Level Info
                }
            } catch {}
        }
        
        # ==========================================================================
        # SMART HEALTH STATUS
        # ==========================================================================
        Write-ForensicsLog "`n--- SMART HEALTH STATUS ---" -Level Info
        
        Write-ForensicsLog "`nDisk Health Status:" -Level Info
        foreach ($disk in $physicalDisks) {
            $health = $disk.HealthStatus
            $operational = $disk.OperationalStatus
            
            Write-ForensicsLog "  $($disk.FriendlyName): Health=$health, Operational=$operational" -Level Info
            
            if ($health -ne "Healthy") {
                Add-Bottleneck -Category "Storage" -Issue "Disk health issue on $($disk.FriendlyName)" `
                    -Value "$health" -Threshold "Healthy" -Impact "Critical"
            }
            
            # Get reliability counters
            $reliability = Get-PhysicalDisk -FriendlyName $disk.FriendlyName | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($reliability) {
                Write-ForensicsLog "    Temperature: $($reliability.Temperature)°C" -Level Info
                Write-ForensicsLog "    Wear: $($reliability.Wear)%" -Level Info
                Write-ForensicsLog "    Read Errors: $($reliability.ReadErrorsTotal)" -Level Info
                Write-ForensicsLog "    Write Errors: $($reliability.WriteErrorsTotal)" -Level Info
                Write-ForensicsLog "    Power On Hours: $($reliability.PowerOnHours)" -Level Info
                
                if ($reliability.Wear -gt 80) {
                    Add-Bottleneck -Category "Storage" -Issue "High SSD wear on $($disk.FriendlyName)" `
                        -Value "$($reliability.Wear)%" -Threshold "80%" -Impact "High"
                }
                
                if ($reliability.Temperature -gt 60) {
                    Add-Bottleneck -Category "Storage" -Issue "High disk temperature on $($disk.FriendlyName)" `
                        -Value "$($reliability.Temperature)°C" -Threshold "60°C" -Impact "Medium"
                }
            }
        }
        
        # ==========================================================================
        # CAPACITY PROFILING
        # ==========================================================================
        Write-ForensicsLog "`n--- CAPACITY PROFILING ---" -Level Info
        
        # Volume capacity
        Write-ForensicsLog "`nVolume Capacity:" -Level Info
        Get-Volume | Where-Object { $_.DriveType -eq "Fixed" -and $_.DriveLetter } | ForEach-Object {
            $vol = $_
            $totalGB = [math]::Round($vol.Size / 1GB, 2)
            $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
            $usedPercent = [math]::Round((($vol.Size - $vol.SizeRemaining) / $vol.Size) * 100, 2)
            
            Write-ForensicsLog "  $($vol.DriveLetter): $($vol.FileSystemLabel) - Used: $usedPercent% ($($totalGB - $freeGB)GB / ${totalGB}GB)" -Level Info
            
            if ($usedPercent -gt 90) {
                Add-Bottleneck -Category "Storage" -Issue "Low disk space on $($vol.DriveLetter):" `
                    -Value "$usedPercent%" -Threshold "90%" -Impact "High"
            }
        }
        
        # Top space consumers
        Write-ForensicsLog "`nTop 10 Directories by Size (C:\):" -Level Info
        $topDirs = Get-ChildItem -Path "C:\" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $size = (Get-ChildItem -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            [PSCustomObject]@{
                Path = $_.FullName
                SizeGB = [math]::Round($size / 1GB, 2)
            }
        } | Sort-Object SizeGB -Descending | Select-Object -First 10
        
        foreach ($dir in $topDirs) {
            Write-ForensicsLog "  $($dir.Path): $($dir.SizeGB) GB" -Level Info
        }
        
        # Large files
        Write-ForensicsLog "`nLarge Files (>1GB) on C:\:" -Level Info
        Get-ChildItem -Path "C:\" -Recurse -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.Length -gt 1GB } | 
            Sort-Object Length -Descending | 
            Select-Object -First 10 | ForEach-Object {
                Write-ForensicsLog "  $($_.FullName): $([math]::Round($_.Length / 1GB, 2)) GB" -Level Info
            }
        
        # Windows component sizes
        Write-ForensicsLog "`nWindows Component Sizes:" -Level Info
        $windowsFolders = @(
            "C:\Windows\WinSxS",
            "C:\Windows\Installer",
            "C:\Windows\SoftwareDistribution",
            "C:\Windows\Temp",
            "$env:TEMP"
        )
        
        foreach ($folder in $windowsFolders) {
            if (Test-Path $folder) {
                $size = (Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                Write-ForensicsLog "  $folder : $([math]::Round($size / 1GB, 2)) GB" -Level Info
            }
        }
        
        # ==========================================================================
        # FILESYSTEM FRAGMENTATION
        # ==========================================================================
        Write-ForensicsLog "`n--- FILESYSTEM FRAGMENTATION ---" -Level Info
        
        Get-Volume | Where-Object { $_.DriveType -eq "Fixed" -and $_.DriveLetter } | ForEach-Object {
            $vol = $_
            Write-ForensicsLog "`nFragmentation Analysis for $($vol.DriveLetter):" -Level Info
            
            try {
                $defragInfo = Optimize-Volume -DriveLetter $vol.DriveLetter -Analyze -Verbose 4>&1
                $defragInfo | ForEach-Object { Write-ForensicsLog "  $_" -Level Info }
            } catch {
                Write-ForensicsLog "  Unable to analyze fragmentation: $_" -Level Warning
            }
        }
        
        # ==========================================================================
        # iSCSI / SAN DETECTION
        # ==========================================================================
        Write-ForensicsLog "`n--- SAN/iSCSI DETECTION ---" -Level Info
        
        # iSCSI connections
        Write-ForensicsLog "`niSCSI Sessions:" -Level Info
        $iscsiSessions = Get-IscsiSession -ErrorAction SilentlyContinue
        if ($iscsiSessions) {
            foreach ($session in $iscsiSessions) {
                Write-ForensicsLog "  Target: $($session.TargetNodeAddress) - Connection: $($session.ConnectionIdentifier)" -Level Info
            }
        } else {
            Write-ForensicsLog "  No active iSCSI sessions" -Level Info
        }
        
        # iSCSI targets
        Write-ForensicsLog "`niSCSI Targets:" -Level Info
        $iscsiTargets = Get-IscsiTarget -ErrorAction SilentlyContinue
        if ($iscsiTargets) {
            foreach ($target in $iscsiTargets) {
                Write-ForensicsLog "  $($target.NodeAddress) - Connected: $($target.IsConnected)" -Level Info
            }
        } else {
            Write-ForensicsLog "  No iSCSI targets configured" -Level Info
        }
        
        # Fibre Channel HBAs
        Write-ForensicsLog "`nFibre Channel HBAs:" -Level Info
        $fcHbas = Get-WmiObject -Class MSFC_FCAdapterHBAAttributes -Namespace "root\WMI" -ErrorAction SilentlyContinue
        if ($fcHbas) {
            foreach ($hba in $fcHbas) {
                Write-ForensicsLog "  $($hba.Manufacturer) - WWPN: $($hba.NodeWWN)" -Level Info
            }
        } else {
            Write-ForensicsLog "  No Fibre Channel HBAs detected" -Level Info
        }
        
        # MPIO paths
        Write-ForensicsLog "`nMultipath I/O:" -Level Info
        $mpio = Get-MSDSMAutomaticClaimSettings -ErrorAction SilentlyContinue
        if ($mpio) {
            Write-ForensicsLog "  MPIO is configured" -Level Info
            Get-MSDSMSupportedHW -ErrorAction SilentlyContinue | ForEach-Object {
                Write-ForensicsLog "    Supported: $($_.VendorId) $($_.ProductId)" -Level Info
            }
        } else {
            Write-ForensicsLog "  MPIO not configured" -Level Info
        }
        
        # ==========================================================================
        # STORAGE PERFORMANCE BASELINE
        # ==========================================================================
        Write-ForensicsLog "`n--- STORAGE PERFORMANCE BASELINE ---" -Level Info
        
        if ($Mode -eq 'Deep' -or $Mode -eq 'DiskOnly') {
            Write-ForensicsLog "Running storage performance baseline tests..." -Level Info
            
            $testPath = Join-Path $env:TEMP "storage_baseline_test"
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null
            $testFile = Join-Path $testPath "test.dat"
            
            try {
                # Sequential Write Test
                Write-ForensicsLog "`nSequential Write Test (1GB):" -Level Info
                $writeTest = Measure-Command {
                    $buffer = New-Object byte[] (1MB)
                    $stream = [System.IO.File]::Create($testFile)
                    for ($i = 0; $i -lt 1024; $i++) {
                        $stream.Write($buffer, 0, $buffer.Length)
                    }
                    $stream.Flush()
                    $stream.Close()
                }
                $writeMBps = [math]::Round(1024 / $writeTest.TotalSeconds, 2)
                Write-ForensicsLog "  Write Speed: $writeMBps MB/s" -Level Info
                
                # Sequential Read Test
                Write-ForensicsLog "`nSequential Read Test (1GB):" -Level Info
                # Clear cache
                [System.GC]::Collect()
                
                $readTest = Measure-Command {
                    $buffer = New-Object byte[] (1MB)
                    $stream = [System.IO.File]::OpenRead($testFile)
                    while ($stream.Read($buffer, 0, $buffer.Length) -gt 0) { }
                    $stream.Close()
                }
                $readMBps = [math]::Round(1024 / $readTest.TotalSeconds, 2)
                Write-ForensicsLog "  Read Speed: $readMBps MB/s" -Level Info
                
                # Random I/O Test (4K blocks)
                Write-ForensicsLog "`nRandom 4K I/O Test:" -Level Info
                $random = New-Object Random
                $smallBuffer = New-Object byte[] 4096
                
                $randomReadTest = Measure-Command {
                    $stream = [System.IO.File]::OpenRead($testFile)
                    for ($i = 0; $i -lt 10000; $i++) {
                        $position = $random.Next(0, [int]($stream.Length / 4096)) * 4096
                        $stream.Seek($position, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $stream.Read($smallBuffer, 0, 4096) | Out-Null
                    }
                    $stream.Close()
                }
                $randomIOPS = [math]::Round(10000 / $randomReadTest.TotalSeconds, 0)
                Write-ForensicsLog "  Random 4K Read IOPS: $randomIOPS" -Level Info
                
            } finally {
                # Cleanup
                Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-ForensicsLog "  Run with -Mode Deep or -Mode DiskOnly for performance baseline tests" -Level Info
        }
        
        $script:DiagnosticData['StorageProfile'] = @{
            PhysicalDisks = $physicalDisks
            NVMeCount = $nvmeCount
            SSDCount = $ssdCount
            HDDCount = $hddCount
        }
        
        Write-ForensicsLog "`nStorage profiling completed" -Level Success
        
    } catch {
        Write-ForensicsLog "Error during storage profiling: $_" -Level Error
    }
}

#endregion

#region Database Forensics

Function Get-DatabaseForensics {
    Write-ForensicsHeader "DATABASE FORENSICS"
    
    Write-ForensicsLog "Scanning for database processes and connections..." -Level Info
    
    $databasesFound = $false
    
    # SQL Server Detection
    $sqlServerProcesses = Get-Process | Where-Object { $_.ProcessName -like "sqlservr*" }
    if ($sqlServerProcesses) {
        $databasesFound = $true
        Write-ForensicsLog "`n=== SQL Server Detected ===" -Level Info
        
        foreach ($proc in $sqlServerProcesses) {
            $cpuPercent = [math]::Round(($proc.CPU / ((Get-Date) - $proc.StartTime).TotalSeconds), 2)
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-ForensicsLog "  Process: PID $($proc.Id), CPU: $cpuPercent%, Memory: $memoryMB MB" -Level Info
        }
        
        # SQL Server connections
        $sqlConnections = (Get-NetTCPConnection -LocalPort 1433 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-ForensicsLog "  Active Connections: $sqlConnections" -Level Info
        
        if ($sqlConnections -gt 500) {
            Add-Bottleneck -Category "Database" -Issue "High SQL Server connection count" `
                -Value "$sqlConnections" -Threshold "500" -Impact "Medium"
        }
        
        # SQL Server Query Analysis (requires SQL authentication)
        try {
            # Try to connect to SQL Server using Windows Authentication
            $sqlQuery = @"
-- Top 5 queries by CPU time
SELECT TOP 5
    qs.execution_count AS [Executions],
    qs.total_worker_time / 1000 AS [Total CPU (ms)],
    qs.total_worker_time / qs.execution_count / 1000 AS [Avg CPU (ms)],
    qs.total_elapsed_time / 1000 AS [Total Duration (ms)],
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS [Query Text]
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_worker_time DESC;

-- Currently executing queries
SELECT 
    r.session_id,
    r.status,
    r.command,
    r.cpu_time,
    r.total_elapsed_time,
    r.wait_type,
    r.wait_time,
    r.blocking_session_id,
    SUBSTRING(qt.text, (r.statement_start_offset/2)+1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE r.statement_end_offset
        END - r.statement_start_offset)/2) + 1) AS [Current Query]
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) qt
WHERE r.session_id > 50
ORDER BY r.total_elapsed_time DESC;
"@
            
            $sqlCmd = "sqlcmd -S localhost -E -Q `"$sqlQuery`" -h -1 -W"
            $queryResults = Invoke-Expression $sqlCmd 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ForensicsLog "`n  SQL Server Query Analysis:" -Level Info
                Write-ForensicsLog "$queryResults" -Level Info
                
                # Check for long-running queries (>30 seconds)
                $longRunning = $queryResults | Select-String "(\d+)\s+running" | ForEach-Object {
                    if ($_.Matches[0].Groups[1].Value -gt 30000) { $_ }
                }
                
                if ($longRunning) {
                    Add-Bottleneck -Category "Database" -Issue "Long-running SQL queries detected (>30s)" `
                        -Value "Yes" -Threshold "30s" -Impact "High"
                }
                
                # Check for blocking
                if ($queryResults -match "blocking_session_id.*[1-9]") {
                    Add-Bottleneck -Category "Database" -Issue "SQL Server blocking detected" `
                        -Value "Yes" -Threshold "No blocking" -Impact "High"
                }
            }
        } catch {
            Write-ForensicsLog "  Unable to query SQL Server DMVs (requires SQL authentication)" -Level Warning
        }
        
        # DMS-specific checks for SQL Server
        try {
            Write-ForensicsLog "`n  DMS Migration Readiness:" -Level Info
            
            # Check SQL Server Agent status
            $agentService = Get-Service -Name "SQLSERVERAGENT" -ErrorAction SilentlyContinue
            if ($agentService) {
                Write-ForensicsLog "    SQL Server Agent: $($agentService.Status)" -Level Info
                if ($agentService.Status -ne "Running") {
                    Add-Bottleneck -Category "DMS" -Issue "SQL Server Agent not running - required for DMS CDC" `
                        -Value "$($agentService.Status)" -Threshold "Running" -Impact "High"
                }
            }
            
            # Check database recovery models
            $recoveryCheck = "SELECT name, recovery_model_desc FROM sys.databases WHERE name NOT IN ('master','model','msdb','tempdb');"
            $recoveryResults = Invoke-Expression "sqlcmd -S localhost -E -Q `"$recoveryCheck`" -h -1 -W" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-ForensicsLog "    Database Recovery Models:" -Level Info
                Write-ForensicsLog "$recoveryResults" -Level Info
                if ($recoveryResults -match "SIMPLE") {
                    Add-Bottleneck -Category "DMS" -Issue "SQL Server database(s) in SIMPLE recovery - DMS CDC requires FULL" `
                        -Value "SIMPLE" -Threshold "FULL" -Impact "High"
                }
            }
            
            # Check for AlwaysOn configuration
            $alwaysOnCheck = "SELECT ar.replica_server_name, drs.synchronization_state_desc, drs.log_send_queue_size, drs.redo_queue_size FROM sys.dm_hadr_database_replica_states drs INNER JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id WHERE drs.is_local = 1;"
            $alwaysOnResults = Invoke-Expression "sqlcmd -S localhost -E -Q `"$alwaysOnCheck`" -h -1 -W" 2>&1
            if ($LASTEXITCODE -eq 0 -and $alwaysOnResults -notmatch "^$") {
                Write-ForensicsLog "    AlwaysOn Replica Status:" -Level Info
                Write-ForensicsLog "$alwaysOnResults" -Level Info
            }
        } catch {
            Write-ForensicsLog "  Unable to check DMS readiness (requires SQL authentication)" -Level Warning
        }
    }
    
    # MySQL/MariaDB Detection
    $mysqlProcesses = Get-Process | Where-Object { $_.ProcessName -like "mysqld*" -or $_.ProcessName -like "mariadbd*" }
    if ($mysqlProcesses) {
        $databasesFound = $true
        Write-ForensicsLog "`n=== MySQL/MariaDB Detected ===" -Level Info
        
        foreach ($proc in $mysqlProcesses) {
            $cpuPercent = [math]::Round(($proc.CPU / ((Get-Date) - $proc.StartTime).TotalSeconds), 2)
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-ForensicsLog "  Process: PID $($proc.Id), CPU: $cpuPercent%, Memory: $memoryMB MB" -Level Info
        }
        
        # MySQL connections
        $mysqlConnections = (Get-NetTCPConnection -LocalPort 3306 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-ForensicsLog "  Active Connections: $mysqlConnections" -Level Info
        
        if ($mysqlConnections -gt 500) {
            Add-Bottleneck -Category "Database" -Issue "High MySQL connection count" `
                -Value "$mysqlConnections" -Threshold "500" -Impact "Medium"
        }
        
        # MySQL Query Analysis
        try {
            $mysqlQuery = @"
SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 100) AS QUERY
FROM information_schema.PROCESSLIST
WHERE COMMAND != 'Sleep' AND TIME > 30
ORDER BY TIME DESC LIMIT 5;

SELECT 
    DIGEST_TEXT AS query,
    COUNT_STAR AS exec_count,
    ROUND(AVG_TIMER_WAIT/1000000000, 2) AS avg_time_ms,
    ROUND(SUM_TIMER_WAIT/1000000000, 2) AS total_time_ms,
    ROUND(SUM_ROWS_EXAMINED/COUNT_STAR, 0) AS avg_rows_examined
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC LIMIT 5;
"@
            
            $mysqlCmd = "mysql -u root -e `"$mysqlQuery`""
            $queryResults = Invoke-Expression $mysqlCmd 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ForensicsLog "`n  MySQL Query Analysis:" -Level Info
                Write-ForensicsLog "$queryResults" -Level Info
                
                if ($queryResults -match "TIME.*[3-9]\d{2,}") {
                    Add-Bottleneck -Category "Database" -Issue "Long-running MySQL queries detected (>30s)" `
                        -Value "Yes" -Threshold "30s" -Impact "High"
                }
            }
        } catch {
            Write-ForensicsLog "  Unable to query MySQL (requires authentication)" -Level Warning
        }
        
        # DMS-specific checks for MySQL
        try {
            Write-ForensicsLog "`n  DMS Migration Readiness:" -Level Info
            
            # Check binary logging
            $binlogStatus = & mysql -u root -e "SHOW VARIABLES LIKE 'log_bin';" 2>&1 | Select-String "ON|OFF"
            Write-ForensicsLog "    Binary Logging: $binlogStatus" -Level Info
            if ($binlogStatus -notmatch "ON") {
                Add-Bottleneck -Category "DMS" -Issue "MySQL binary logging disabled - required for CDC" `
                    -Value "OFF" -Threshold "ON" -Impact "High"
            }
            
            # Check binlog format
            $binlogFormat = & mysql -u root -e "SHOW VARIABLES LIKE 'binlog_format';" 2>&1 | Select-String "ROW|STATEMENT|MIXED"
            Write-ForensicsLog "    Binary Log Format: $binlogFormat" -Level Info
            if ($binlogFormat -notmatch "ROW") {
                Add-Bottleneck -Category "DMS" -Issue "MySQL binlog format not ROW - required for DMS CDC" `
                    -Value "$binlogFormat" -Threshold "ROW" -Impact "High"
            }
            
            # Check binlog retention
            $binlogRetention = & mysql -u root -e "SHOW VARIABLES LIKE 'expire_logs_days';" 2>&1 | Select-String "\d+"
            Write-ForensicsLog "    Binary Log Retention: $binlogRetention days" -Level Info
            
            # Check replication lag
            $slaveStatus = & mysql -u root -e "SHOW SLAVE STATUS\G" 2>&1 | Select-String "Seconds_Behind_Master"
            if ($slaveStatus -and $slaveStatus -notmatch "NULL") {
                Write-ForensicsLog "    Replication Lag: $slaveStatus" -Level Info
            }
        } catch {
            Write-ForensicsLog "  Unable to check MySQL DMS readiness (requires authentication)" -Level Warning
        }
    }
    
    # PostgreSQL Detection
    $postgresProcesses = Get-Process | Where-Object { $_.ProcessName -like "postgres*" }
    if ($postgresProcesses) {
        $databasesFound = $true
        Write-ForensicsLog "`n=== PostgreSQL Detected ===" -Level Info
        
        $mainProcess = $postgresProcesses | Sort-Object StartTime | Select-Object -First 1
        $cpuPercent = [math]::Round(($mainProcess.CPU / ((Get-Date) - $mainProcess.StartTime).TotalSeconds), 2)
        $memoryMB = [math]::Round($mainProcess.WorkingSet64 / 1MB, 2)
        Write-ForensicsLog "  Process: PID $($mainProcess.Id), CPU: $cpuPercent%, Memory: $memoryMB MB" -Level Info
        
        # PostgreSQL connections
        $pgConnections = (Get-NetTCPConnection -LocalPort 5432 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-ForensicsLog "  Active Connections: $pgConnections" -Level Info
        
        if ($pgConnections -gt 500) {
            Add-Bottleneck -Category "Database" -Issue "High PostgreSQL connection count" `
                -Value "$pgConnections" -Threshold "500" -Impact "Medium"
        }
        
        # PostgreSQL Query Analysis
        try {
            $pgQuery = @"
SELECT pid, usename, application_name, state, 
       EXTRACT(EPOCH FROM (now() - query_start)) AS duration_seconds,
       LEFT(query, 100) AS query
FROM pg_stat_activity
WHERE state != 'idle' AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration_seconds DESC LIMIT 5;

SELECT query, calls, 
       ROUND(total_exec_time::numeric, 2) AS total_time_ms,
       ROUND(mean_exec_time::numeric, 2) AS avg_time_ms,
       ROUND((100 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) AS pct_total
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 5;
"@
            
            $pgCmd = "psql -U postgres -c `"$pgQuery`""
            $queryResults = Invoke-Expression $pgCmd 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ForensicsLog "`n  PostgreSQL Query Analysis:" -Level Info
                Write-ForensicsLog "$queryResults" -Level Info
                
                if ($queryResults -match "duration_seconds.*[3-9]\d+") {
                    Add-Bottleneck -Category "Database" -Issue "Long-running PostgreSQL queries detected (>30s)" `
                        -Value "Yes" -Threshold "30s" -Impact "High"
                }
            }
        } catch {
            Write-ForensicsLog "  Unable to query PostgreSQL (requires authentication)" -Level Warning
        }
        
        # DMS-specific checks for PostgreSQL
        try {
            Write-ForensicsLog "`n  DMS Migration Readiness:" -Level Info
            
            # Check WAL level
            $walLevel = & psql -U postgres -t -c "SHOW wal_level;" 2>&1
            Write-ForensicsLog "    WAL Level: $($walLevel.Trim())" -Level Info
            if ($walLevel -notmatch "logical") {
                Add-Bottleneck -Category "DMS" -Issue "PostgreSQL wal_level not 'logical' - required for DMS CDC" `
                    -Value "$($walLevel.Trim())" -Threshold "logical" -Impact "High"
            }
            
            # Check replication slots
            $replSlots = & psql -U postgres -t -c "SELECT COUNT(*) FROM pg_replication_slots;" 2>&1
            Write-ForensicsLog "    Replication Slots: $($replSlots.Trim())" -Level Info
            
            # Check max_replication_slots
            $maxSlots = & psql -U postgres -t -c "SHOW max_replication_slots;" 2>&1
            Write-ForensicsLog "    Max Replication Slots: $($maxSlots.Trim())" -Level Info
            if ($maxSlots -match "^\s*0\s*$") {
                Add-Bottleneck -Category "DMS" -Issue "PostgreSQL max_replication_slots is 0 - DMS requires at least 1" `
                    -Value "0" -Threshold ">=1" -Impact "High"
            }
            
            # Check if standby
            $isStandby = & psql -U postgres -t -c "SELECT pg_is_in_recovery();" 2>&1
            if ($isStandby -match "t") {
                $lag = & psql -U postgres -t -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));" 2>&1
                Write-ForensicsLog "    Replication Lag: $($lag.Trim()) seconds" -Level Info
            }
        } catch {
            Write-ForensicsLog "  Unable to check PostgreSQL DMS readiness (requires authentication)" -Level Warning
        }
    }
    
    # MongoDB Detection
    $mongoProcesses = Get-Process | Where-Object { $_.ProcessName -like "mongod*" }
    if ($mongoProcesses) {
        $databasesFound = $true
        Write-ForensicsLog "`n=== MongoDB Detected ===" -Level Info
        
        foreach ($proc in $mongoProcesses) {
            $cpuPercent = [math]::Round(($proc.CPU / ((Get-Date) - $proc.StartTime).TotalSeconds), 2)
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-ForensicsLog "  Process: PID $($proc.Id), CPU: $cpuPercent%, Memory: $memoryMB MB" -Level Info
        }
        
        # MongoDB connections
        $mongoConnections = (Get-NetTCPConnection -LocalPort 27017 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-ForensicsLog "  Active Connections: $mongoConnections" -Level Info
        
        if ($mongoConnections -gt 1000) {
            Add-Bottleneck -Category "Database" -Issue "High MongoDB connection count" `
                -Value "$mongoConnections" -Threshold "1000" -Impact "Medium"
        }
        
        # MongoDB Query Analysis
        try {
            $mongoQuery = @"
db.currentOp({`$or: [{op: {`$in: ['query', 'command']}}, {secs_running: {`$gte: 30}}]}).inprog.forEach(function(op) {
    print('OpID: ' + op.opid + ' | Duration: ' + op.secs_running + 's | NS: ' + op.ns + ' | Query: ' + JSON.stringify(op.command).substring(0,100));
});
print('---TOP 5 SLOWEST OPERATIONS---');
db.system.profile.find().sort({millis: -1}).limit(5).forEach(function(op) {
    print('Duration: ' + op.millis + 'ms | Op: ' + op.op + ' | NS: ' + op.ns + ' | Query: ' + JSON.stringify(op.command).substring(0,100));
});
"@
            
            $mongoCmd = "mongo --quiet --eval `"$mongoQuery`""
            $queryResults = Invoke-Expression $mongoCmd 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ForensicsLog "`n  MongoDB Query Analysis:" -Level Info
                Write-ForensicsLog "$queryResults" -Level Info
                
                if ($queryResults -match "Duration: [3-9]\d+s") {
                    Add-Bottleneck -Category "Database" -Issue "Long-running MongoDB operations detected (>30s)" `
                        -Value "Yes" -Threshold "30s" -Impact "High"
                }
            }
        } catch {
            Write-ForensicsLog "  Unable to query MongoDB (requires authentication or profiling enabled)" -Level Warning
        }
    }
    
    # Redis Detection
    $redisProcesses = Get-Process | Where-Object { $_.ProcessName -like "redis-server*" }
    if ($redisProcesses) {
        $databasesFound = $true
        Write-ForensicsLog "`n=== Redis Detected ===" -Level Info
        
        foreach ($proc in $redisProcesses) {
            $cpuPercent = [math]::Round(($proc.CPU / ((Get-Date) - $proc.StartTime).TotalSeconds), 2)
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-ForensicsLog "  Process: PID $($proc.Id), CPU: $cpuPercent%, Memory: $memoryMB MB" -Level Info
        }
        
        # Redis connections
        $redisConnections = (Get-NetTCPConnection -LocalPort 6379 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-ForensicsLog "  Active Connections: $redisConnections" -Level Info
        
        if ($redisConnections -gt 10000) {
            Add-Bottleneck -Category "Database" -Issue "High Redis connection count" `
                -Value "$redisConnections" -Threshold "10000" -Impact "Medium"
        }
        
        # Redis Performance Analysis
        try {
            $redisInfo = redis-cli INFO stats 2>&1
            $redisSlowlog = redis-cli SLOWLOG GET 5 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ForensicsLog "`n  Redis Performance Metrics:" -Level Info
                
                # Parse key metrics
                $totalCommands = ($redisInfo | Select-String "total_commands_processed:(\d+)").Matches.Groups[1].Value
                $opsPerSec = ($redisInfo | Select-String "instantaneous_ops_per_sec:(\d+)").Matches.Groups[1].Value
                $rejectedConns = ($redisInfo | Select-String "rejected_connections:(\d+)").Matches.Groups[1].Value
                
                Write-ForensicsLog "  Total Commands: $totalCommands | Ops/sec: $opsPerSec | Rejected Connections: $rejectedConns" -Level Info
                Write-ForensicsLog "`n  Top 5 Slow Commands:" -Level Info
                Write-ForensicsLog "$redisSlowlog" -Level Info
                
                if ([int]$rejectedConns -gt 0) {
                    Add-Bottleneck -Category "Database" -Issue "Redis connection rejections detected" `
                        -Value "$rejectedConns" -Threshold "0" -Impact "High"
                }
            }
        } catch {
            Write-ForensicsLog "  Unable to query Redis (requires redis-cli)" -Level Warning
        }
    }
    
    # Cassandra Detection
    $cassandraProcesses = Get-Process | Where-Object { $_.ProcessName -like "java*" -and $_.CommandLine -like "*cassandra*" }
    if ($cassandraProcesses) {
        $databasesFound = $true
        Write-ForensicsLog "`n=== Cassandra Detected ===" -Level Info
        
        foreach ($proc in $cassandraProcesses) {
            $cpuPercent = [math]::Round(($proc.CPU / ((Get-Date) - $proc.StartTime).TotalSeconds), 2)
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-ForensicsLog "  Process: PID $($proc.Id), CPU: $cpuPercent%, Memory: $memoryMB MB" -Level Info
        }
        
        # Cassandra connections
        $cassandraConnections = (Get-NetTCPConnection -LocalPort 9042 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-ForensicsLog "  Active Connections: $cassandraConnections" -Level Info
        
        if ($cassandraConnections -gt 1000) {
            Add-Bottleneck -Category "Database" -Issue "High Cassandra connection count" `
                -Value "$cassandraConnections" -Threshold "1000" -Impact "Medium"
        }
    }
    
    # Elasticsearch Detection
    $elasticsearchProcesses = Get-Process | Where-Object { $_.ProcessName -like "java*" -and $_.CommandLine -like "*elasticsearch*" }
    if ($elasticsearchProcesses) {
        $databasesFound = $true
        Write-ForensicsLog "`n=== Elasticsearch Detected ===" -Level Info
        
        foreach ($proc in $elasticsearchProcesses) {
            $cpuPercent = [math]::Round(($proc.CPU / ((Get-Date) - $proc.StartTime).TotalSeconds), 2)
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-ForensicsLog "  Process: PID $($proc.Id), CPU: $cpuPercent%, Memory: $memoryMB MB" -Level Info
        }
        
        # Elasticsearch connections
        $esConnections = (Get-NetTCPConnection -LocalPort 9200 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-ForensicsLog "  Active Connections: $esConnections" -Level Info
        
        # Elasticsearch Query Analysis
        try {
            # Get current tasks
            $esTasks = Invoke-RestMethod -Uri "http://localhost:9200/_tasks?detailed=true&actions=*search*" -Method Get 2>&1
            
            # Get slow queries from slow log
            $esSlowLog = Invoke-RestMethod -Uri "http://localhost:9200/_all/_settings?include_defaults=true" -Method Get 2>&1
            
            # Get thread pool stats
            $esThreadPool = Invoke-RestMethod -Uri "http://localhost:9200/_cat/thread_pool?v&h=node_name,name,active,queue,rejected" -Method Get 2>&1
            
            Write-ForensicsLog "`n  Elasticsearch Performance Analysis:" -Level Info
            
            # Parse active tasks
            if ($esTasks.tasks) {
                $longRunning = $esTasks.tasks.PSObject.Properties | Where-Object { 
                    $_.Value.running_time_in_nanos / 1000000000 -gt 30 
                }
                
                if ($longRunning) {
                    Write-ForensicsLog "  Long-running queries detected:" -Level Warning
                    foreach ($task in $longRunning | Select-Object -First 5) {
                        $duration = [math]::Round($task.Value.running_time_in_nanos / 1000000000, 2)
                        Write-ForensicsLog "    Task: $($task.Value.action) | Duration: ${duration}s" -Level Info
                    }
                    
                    Add-Bottleneck -Category "Database" -Issue "Long-running Elasticsearch queries detected (>30s)" `
                        -Value "Yes" -Threshold "30s" -Impact "High"
                }
            }
            
            # Check thread pool rejections
            Write-ForensicsLog "`n  Thread Pool Status:" -Level Info
            Write-ForensicsLog "$esThreadPool" -Level Info
            
            if ($esThreadPool -match "rejected.*[1-9]") {
                Add-Bottleneck -Category "Database" -Issue "Elasticsearch thread pool rejections detected" `
                    -Value "Yes" -Threshold "0" -Impact "High"
            }
            
        } catch {
            Write-ForensicsLog "  Unable to query Elasticsearch API (requires HTTP access to localhost:9200)" -Level Warning
        }
    }
    
    # Oracle Detection
    $oracleProcesses = Get-Process | Where-Object { $_.ProcessName -like "oracle*" }
    if ($oracleProcesses) {
        $databasesFound = $true
        Write-ForensicsLog "`n=== Oracle Database Detected ===" -Level Info
        
        foreach ($proc in $oracleProcesses | Select-Object -First 1) {
            $cpuPercent = [math]::Round(($proc.CPU / ((Get-Date) - $proc.StartTime).TotalSeconds), 2)
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-ForensicsLog "  Process: PID $($proc.Id), CPU: $cpuPercent%, Memory: $memoryMB MB" -Level Info
        }
        
        # Oracle connections
        $oracleConnections = (Get-NetTCPConnection -LocalPort 1521 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-ForensicsLog "  Active Connections: $oracleConnections" -Level Info
        
        if ($oracleConnections -gt 500) {
            Add-Bottleneck -Category "Database" -Issue "High Oracle connection count" `
                -Value "$oracleConnections" -Threshold "500" -Impact "Medium"
        }
        
        # Oracle Query Analysis
        try {
            Write-ForensicsLog "`n  Oracle Query Analysis:" -Level Info
            
            # Active sessions query
            $sessionQuery = "SELECT sid, serial#, username, status, ROUND(last_call_et/60, 2) AS duration_min, sql_id, blocking_session, event FROM v`$session WHERE status = 'ACTIVE' AND username IS NOT NULL ORDER BY last_call_et DESC FETCH FIRST 5 ROWS ONLY;"
            $sessionResults = echo $sessionQuery | sqlplus -S / as sysdba 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ForensicsLog "$sessionResults" -Level Info
                
                if ($sessionResults -match "duration_min.*[3-9]\d+") {
                    Add-Bottleneck -Category "Database" -Issue "Long-running Oracle sessions detected (>30min)" `
                        -Value "Yes" -Threshold "30min" -Impact "High"
                }
                
                if ($sessionResults -match "blocking_session.*[1-9]") {
                    Add-Bottleneck -Category "Database" -Issue "Oracle blocking sessions detected" `
                        -Value "Yes" -Threshold "No blocking" -Impact "High"
                }
            }
            
            # Top queries by elapsed time
            $sqlQuery = "SELECT sql_id, executions, ROUND(elapsed_time/1000000, 2) AS total_time_sec, ROUND(cpu_time/1000000, 2) AS cpu_time_sec, ROUND(buffer_gets/NULLIF(executions,0), 0) AS avg_buffer_gets FROM v`$sql ORDER BY elapsed_time DESC FETCH FIRST 5 ROWS ONLY;"
            $sqlResults = echo $sqlQuery | sqlplus -S / as sysdba 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ForensicsLog "$sqlResults" -Level Info
            }
        } catch {
            Write-ForensicsLog "  Unable to query Oracle (requires sqlplus and authentication)" -Level Warning
        }
        
        # DMS-specific checks for Oracle
        try {
            Write-ForensicsLog "`n  DMS Migration Readiness:" -Level Info
            
            # Check ARCHIVELOG mode
            $archiveMode = echo "SELECT log_mode FROM v`$database;" | sqlplus -S / as sysdba 2>&1 | Select-String "ARCHIVELOG|NOARCHIVELOG"
            Write-ForensicsLog "    Archive Log Mode: $archiveMode" -Level Info
            if ($archiveMode -notmatch "ARCHIVELOG") {
                Add-Bottleneck -Category "DMS" -Issue "Oracle not in ARCHIVELOG mode - required for DMS CDC" `
                    -Value "$archiveMode" -Threshold "ARCHIVELOG" -Impact "High"
            }
            
            # Check supplemental logging
            $suppLog = echo "SELECT supplemental_log_data_min FROM v`$database;" | sqlplus -S / as sysdba 2>&1 | Select-String "YES|NO"
            Write-ForensicsLog "    Supplemental Logging: $suppLog" -Level Info
            if ($suppLog -notmatch "YES") {
                Add-Bottleneck -Category "DMS" -Issue "Oracle supplemental logging not enabled - required for DMS CDC" `
                    -Value "$suppLog" -Threshold "YES" -Impact "High"
            }
            
            # Check for Data Guard lag
            $standbyLag = echo "SELECT MAX(ROUND((SYSDATE - applied_time) * 24 * 60)) FROM v`$archived_log WHERE applied = 'YES';" | sqlplus -S / as sysdba 2>&1 | Select-String "\d+"
            if ($standbyLag) {
                Write-ForensicsLog "    Standby Apply Lag: $standbyLag minutes" -Level Info
            }
        } catch {
            Write-ForensicsLog "  Unable to check Oracle DMS readiness (requires sqlplus and authentication)" -Level Warning
        }
    }
    
    # General database connection analysis
    if ($databasesFound) {
        Write-ForensicsLog "`n=== Database Connection Summary ===" -Level Info
        
        # Check for connection churn on database ports
        $dbPorts = @(1433, 3306, 5432, 27017, 6379, 9042, 1521, 9200)
        $totalTimeWait = 0
        
        foreach ($port in $dbPorts) {
            $timeWaitCount = (Get-NetTCPConnection -LocalPort $port -State TimeWait -ErrorAction SilentlyContinue | Measure-Object).Count
            $totalTimeWait += $timeWaitCount
        }
        
        if ($totalTimeWait -gt 1000) {
            Write-ForensicsLog "  High TIME_WAIT on database ports: $totalTimeWait" -Level Warning
            Add-Bottleneck -Category "Database" -Issue "High connection churn (TIME_WAIT)" `
                -Value "$totalTimeWait" -Threshold "1000" -Impact "Medium"
        }
        
        Write-ForensicsLog "`nDatabase forensics completed" -Level Success
    } else {
        Write-ForensicsLog "No common database processes detected" -Level Info
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
    
    # Get instance ID if on AWS, otherwise use hostname
    $instanceId = $null
    try {
        $instanceId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" -TimeoutSec 2 -ErrorAction SilentlyContinue
    } catch {
        # Not on AWS
    }
    
    $systemIdentifier = if ($instanceId) { $instanceId } else { $sysInfo.ComputerName }
    
    $caseSubject = "Windows Performance Issues Detected - $systemIdentifier"
    
    $bottleneckSummary = $script:Bottlenecks | ForEach-Object {
        "[$($_.Impact)] $($_.Category): $($_.Issue) (Current: $($_.CurrentValue), Threshold: $($_.Threshold))"
    } | Out-String
    
    $caseDescription = @"
AUTOMATED WINDOWS FORENSICS REPORT

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
    Write-Host "║                WINDOWS PERFORMANCE FORENSICS TOOL v2.0                    ║" -ForegroundColor Cyan
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
            Get-StorageProfile
            Get-CPUForensics
            Get-MemoryForensics
            Get-DatabaseForensics
        }
        'Deep' {
            Get-PerformanceCounters
            Test-DiskPerformance
            Get-StorageProfile
            Get-CPUForensics
            Get-MemoryForensics
            Get-DatabaseForensics
        }
        'DiskOnly' {
            Get-PerformanceCounters
            Test-DiskPerformance
            Get-StorageProfile
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
        Write-Host "`n" -NoNewline -ForegroundColor Green
        Write-Host "NO BOTTLENECKS FOUND! System performance looks healthy." -ForegroundColor Green
    } else {
        Write-Host "`n" -NoNewline -ForegroundColor Magenta
        Write-Host "BOTTLENECKS DETECTED: $($script:Bottlenecks.Count) performance issue(s) found" -ForegroundColor Magenta
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
            Write-Host "`nAWS Support case created: $caseId" -ForegroundColor Green
        }
    } elseif ($script:Bottlenecks.Count -gt 0 -and -not $CreateSupportCase) {
        Write-Host "`nTip: Run with -CreateSupportCase to automatically open an AWS Support case" -ForegroundColor Cyan
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
