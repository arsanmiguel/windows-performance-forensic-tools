## This is an AWS-provided set of scripts to help customers and partners diagnose client-side performance issues, such as IO constraints and network saturation, specifically when using DMS to migrate customer workloads to AWS. 

##Depending on your source, even if another AWS account, you may have had your default counters suppressed or otherwise, disabled by GPO or registry key. This will reset all performance monitor counters to OS defaults, resynch all performance monitors, restart the Windows Management Instrumentation (WMI) service, restart the Performance Logs & Alerts (PLA) service, and return you to your home directory. 

cd c:\windows\system32
lodctr /R
cd c:\windows\sysWOW64
lodctr /R
winmgmt.exe /resyncperf
Get-Service -Name "pla" | Restart-Service -Verbose
Get-Service -Name "winmgmt" | Restart-Service -Force -Verbose
cd ~/

##The next portion of the script will give you, the user, insight into what is happening in the most commonly found bottlenecks for customers and partners. You will pull the statistics for key Physical Disk, CPU, Memory, and Network Interface counters. Note: unless MSSQL is installed on C: (and hopefully isn't) - you won't find much here. Feel free to add more counters, but these are the most frequent counters used for identifying bottlenecks on migrations. 

$counters = @(
   '\PhysicalDisk(**)\% Idle Time'
   '\PhysicalDisk(**)\Avg. Disk sec/Read'
   '\PhysicalDisk(**)\Avg. Disk sec/Write'
   '\PhysicalDisk(**)\Avg. Disk sec/Transfer'
   '\PhysicalDisk(**)\Disk Reads/sec'
   '\PhysicalDisk(**)\Disk Writes/sec'
   '\PhysicalDisk(**)\Disk Transfers/sec'
   '\PhysicalDisk(**)\Current Disk Queue Length'
   '\PhysicalDisk(**)\Avg. Disk Queue Length'
   '\Processor(**)\% Processor time'
   '\Processor(**)\% Privileged time'
   '\Processor(**)\% user time'
   '\Processor(**)\% idle time'
   '\Processor(**)\DPCs Queued/sec'
   '\Memory\Available Bytes'
   '\Memory\Pages/sec'
   '\Network Interface(**)\Bytes Total/sec'
   '\Network Interface(**)\Output Queue Length'
 ) 

##This final section will take the counters, declared as variables from the previous section, and make it human readable, and re-name a few of the column headers. We will then pull counters over 3 different intervals, and is most useful for customers to run this when they start seeing problems with their MSSQL server when DMS is in use. Finally, we will declare a variable for the output's filename, append today's date to it, and then call that variable to save the results to a file for reference.  

$samples = foreach ($counter in $counters) {
   $sample = (Get-Counter -Counter $counter -sampleinterval 3).CounterSamples
   [pscustomobject]@{
     Category = $sample.Path.Split('\')[3]
     Counter = $sample.Path.Split('\')[4]
     Instance = $sample.InstanceName
     Value = [math]::Round($sample.CookedValue[0])
   }
 }

$filename = "perfmon_results-" + (Get-Date).tostring("dd-MM-yyyy-hh-mm-ss") 
$samples | Out-File $filename

##Please use the output of the perfmon.txt file to open a support case if needed to further troubleshoot. Without this granular information, it is difficult in order to receive timely assitance. 
