param(
    [Parameter(Mandatory)]
    [string]$CsvPath,
    [string]$TaskName = "Invoke-FirmwareUpgrade-TS",
    [string]$RemoteScriptPath = "C:\Windows\Temp\RemoteTS_Action.ps1"
)

$taskUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$remoteScriptContent = @'
param(
    [string]$TaskName = ''
)
# --- CONFIGURATION ---
$TSName = "Install Software Updates - Firmware Upgrade - T0"  # Target Task Sequence Name (or use PackageID)
# ---------------------

# 1. Query the local SCCM client WMI repository for the Task Sequence
$TS = Get-CimInstance -Namespace "root\ccm\clientSDK" -ClassName "CCM_Program" | 
      Where-Object { $_.Name -like "*$TSName*" -or $_.PackageID -eq $TSName }

if ($TS) {
    Write-Host "Found Task Sequence: $($TS.Name) [Package ID: $($TS.PackageID)]" -ForegroundColor Green
    
    # 2. Prepare arguments for execution
    $Args = @{
        PackageID = $TS.PackageID
        ProgramID = $TS.ProgramID
    }
    
    # 3. Trigger the Task Sequence execution
    Write-Host "Triggering execution..." -ForegroundColor Yellow
    Invoke-CimMethod -Namespace "root\ccm\clientSDK" -ClassName "CCM_ProgramsManager" -MethodName "ExecuteProgram" -Arguments $Args | Out-Null
    
    Write-Host "Task Sequence triggered successfully." -ForegroundColor Green
} else {
    Write-Error "Task Sequence '$TSName' not found. Ensure it is deployed to this machine."
}

if ($TaskName) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}
Remove-Item -Path $PSCommandPath -Force -ErrorAction SilentlyContinue
'@

$servers = Import-Csv -Path $CsvPath
if (-not ($servers | Get-Member -Name "ServerName") -or -not ($servers | Get-Member -Name "RebootTime")) {
    throw "CSV must contain 'ServerName' and 'RebootTime' columns."
}

$jobs = foreach ($row in $servers) {
    $target = $row.ServerName.Trim()
    $rebootTimeString = $row.RebootTime.Trim()

    Invoke-Command -ComputerName $target -AsJob -ScriptBlock {
        param($RebootTimeString, $TaskName, $ServerName, $RemoteScriptContent, $RemoteScriptPath, $TaskUser)

        $rebootTime = [DateTime]$RebootTimeString

        if ($rebootTime -le [DateTime]::Now) {
            return [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Result       = "RebootTime is in the past; no task scheduled"
            }
        }

        $null = New-Item -ItemType Directory -Path (Split-Path $RemoteScriptPath) -Force -ErrorAction SilentlyContinue
        Set-Content -Path $RemoteScriptPath -Value $RemoteScriptContent -Force

        $taskName = "$TaskName"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$RemoteScriptPath`" -TaskName `"$taskName`""
        $trigger = New-ScheduledTaskTrigger -Once -At $rebootTime
        $principal = New-ScheduledTaskPrincipal -UserId $TaskUser -LogonType S4U -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        try {
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                TaskName     = $taskName
                TriggerAt    = $rebootTime
                ScriptPath   = $RemoteScriptPath
                RunAs        = $TaskUser
                Result       = "Scheduled task created"
            }
        } catch {
            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                TaskName     = $taskName
                TriggerAt    = $rebootTime
                ScriptPath   = $RemoteScriptPath
                RunAs        = $TaskUser
                Result       = "Failed: $_"
            }
        }
    } -ArgumentList $rebootTimeString, $TaskName, $target, $remoteScriptContent, $RemoteScriptPath, $taskUser
}

Write-Host "Started $(@($jobs).Count) background job(s) to create scheduled tasks." -ForegroundColor Cyan
$jobs | Wait-Job | Out-Null
$jobs | Receive-Job | Format-Table -AutoSize