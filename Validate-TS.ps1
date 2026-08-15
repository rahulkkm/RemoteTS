param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$TaskName = "Invoke-FirmwareUpgrade-TS",

    [string]$RemoteScriptPath = "C:\Windows\Temp\RemoteTS_Action.ps1",

    [string]$TSName = "Install Software Updates - Firmware Upgrade - T0"
)

$servers = Import-Csv -Path $CsvPath

if (-not ($servers | Get-Member -Name "ServerName")) {
    throw "CSV must contain a 'ServerName' column."
}

$results = foreach ($row in $servers) {

    $server = $row.ServerName.Trim()

    try {

        Invoke-Command -ComputerName $server -ScriptBlock {

            param(
                $TaskName,
                $RemoteScriptPath,
                $TSName
            )

            # SCCM Client Status
            $ccmService = Get-Service -Name CcmExec -ErrorAction SilentlyContinue

            # Verify TS Script Exists
            $scriptExists = Test-Path $RemoteScriptPath

            # Locate Scheduled Task
            $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

            $scheduleTime = "NOT FOUND"

            if ($task) {
                try {
                    $scheduleTime = (Get-ScheduledTaskInfo -TaskName $TaskName).NextRunTime
                }
                catch {
                    $scheduleTime = "Unable to Read"
                }
            }

            # Check Task Sequence Visibility
            $tsFound = $null

            try {
                $tsFound = Get-CimInstance `
                    -Namespace "root\ccm\clientSDK" `
                    -ClassName "CCM_Program" `
                    -ErrorAction Stop |
                    Where-Object {
                        $_.Name -like "*$TSName*" -or
                        $_.PackageID -eq $TSName
                    } |
                    Select-Object -First 1
            }
            catch {
                $tsFound = $null
            }

            [PSCustomObject]@{
                ServerName   = $env:COMPUTERNAME
                SCCMClient   = if ($ccmService) { $ccmService.Status } else { "Not Found" }
                TSName       = if ($tsFound) { $tsFound.Name } else { "NOT FOUND" }
                PackageID    = if ($tsFound) { $tsFound.PackageID } else { "NOT FOUND" }
                TSScript     = if ($scriptExists) { $RemoteScriptPath } else { "NOT FOUND" }
                TaskName     = if ($task) { $task.TaskName } else { "NOT FOUND" }
                ScheduleTime = $scheduleTime
            }

        } -ArgumentList $TaskName, $RemoteScriptPath, $TSName

    }
    catch {

        [PSCustomObject]@{
            ServerName   = $server
            SCCMClient   = "Connection Failed"
            TSName       = "NOT AVAILABLE"
            PackageID    = "NOT AVAILABLE"
            TSScript     = "NOT AVAILABLE"
            TaskName     = "NOT AVAILABLE"
            ScheduleTime = "NOT AVAILABLE"
        }
    }
}

# Remove remoting properties
$results = $results | Select-Object `
    ServerName,
    SCCMClient,
    TSName,
    PackageID,
    TSScript,
    TaskName,
    ScheduleTime

# Display Results
$results | Format-Table -AutoSize

# Export Report
$reportFile = ".\TSValidation_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

$results | Export-Csv `
    -Path $reportFile `
    -NoTypeInformation

Write-Host ""
Write-Host "Validation report exported to: $reportFile" -ForegroundColor Green