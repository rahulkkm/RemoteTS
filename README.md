# RemoteTS Scripts

This repository contains PowerShell scripts for managing SCCM Task Sequence deployments across multiple servers via scheduled tasks.

## Scripts

### ScheduleRemoteTS.ps1

Creates one-time Windows Scheduled Tasks on remote servers to trigger SCCM Task Sequences at specific times.

**Purpose:**
- Use this approach if you don't want to manage collections and deployments from the SCCM console
- Schedules a Task Sequence to run at a specific time on each server from a CSV list
- The scheduled task runs as the account executing the script using S4U (no password stored)

**Parameters:**
- `CsvPath` (required) — Path to CSV file with `ServerName` and `RebootTime` columns
- `TaskName` (default: `"Invoke-FirmwareUpgrade-TS"`) — Name of the scheduled task (same for all servers)
- `RemoteScriptPath` (default: `"C:\Windows\Temp\RemoteTS_Action.ps1"`) — Path where the trigger script will be copied on remote servers

**CSV Format:**
```csv
ServerName,RebootTime
SRV-01,2026-08-12 02:00:00
SRV-02,2026-08-12 02:15:00
```

**Usage:**
```powershell
# Run with defaults
.\ScheduleRemoteTS.ps1 -CsvPath ".\servers.csv"

# Specify custom task name and script path
.\ScheduleRemoteTS.ps1 -CsvPath ".\servers.csv" -TaskName "Firmware-Upgrade" -RemoteScriptPath "D:\Scripts\TS_Action.ps1"
```

**Requirements:**
- PowerShell remoting enabled on target servers
- Run as an account with admin rights on target servers
- The account running the script must have the TS deployed to it (for `CCM_Program` visibility)
- Edit the `$TSName` variable in the script to match your Task Sequence name or PackageID

**Notes:**
- The script creates a one-time scheduled task on each server at the specified `RebootTime`
- All servers use the same task name (specified by the `-TaskName` parameter)
- The task runs as the account executing the script using S4U logon type (no password stored)
- After the task runs, it automatically deletes itself and the trigger script
- If `RebootTime` is in the past, that server is skipped
- The TS name is hardcoded in the script — update line 15 to change it

---

### Validate-TS.ps1

Validates Task Sequence deployment status across multiple servers from a CSV list.

**Purpose:**
- Checks SCCM client health, TS visibility, scheduled task status, and script deployment
- Generates a CSV report for audit/troubleshooting

**Parameters:**
- `CsvPath` (required) — Path to CSV file with `ServerName` column
- `TaskName` (default: `"Invoke-FirmwareUpgrade-TS"`) — Name of the scheduled task to check
- `RemoteScriptPath` (default: `"C:\Windows\Temp\RemoteTS_Action.ps1"`) — Path to the TS trigger script on remote servers
- `TSName` (default: `"Install Software Updates - Firmware Upgrade - T0"`) — Task Sequence name or PackageID to validate

**CSV Format:**
```csv
ServerName
SRV-01
SRV-02
SRV-03
```

**Usage:**
```powershell
# Run with defaults
.\Validate-TS.ps1 -CsvPath ".\servers.csv"

# Specify custom TS name and task name
.\Validate-TS.ps1 -CsvPath ".\servers.csv" -TSName "DSU PrePatch Scan" -TaskName "RemoteTS-Trigger"
```

**Validation Checks:**
- **SCCM Client** — Status of the `CcmExec` service
- **TS Name** — Whether the TS is visible in `CCM_Program` WMI class
- **PackageID** — Package ID of the matched TS
- **TS Script** — Whether the trigger script exists at the specified path
- **Task Name** — Whether the scheduled task exists
- **Schedule Time** — Next run time of the scheduled task

**Output:**
- Console table showing validation results for each server
- CSV report exported as `TSValidation_YYYYMMDD_HHMMSS.csv` in the current directory

**Requirements:**
- PowerShell remoting enabled on target servers
- Run as an account with admin rights on target servers
- The account running the script must have the TS deployed to it (for `CCM_Program` visibility)

**Notes:**
- If a server is unreachable, it reports "Connection Failed" for all checks
- The TS visibility check runs in the context of the account running the script
- Use this script before scheduling to ensure all prerequisites are met

---

## Common Use Case: Scheduling a Task Sequence

To schedule a Task Sequence across multiple servers at specific times:

1. **Validate prerequisites** with `Validate-TS.ps1`:
   ```powershell
   .\Validate-TS.ps1 -CsvPath ".\servers.csv" -TSName "Your TS Name"
   ```

2. **Update the TS name** in `ScheduleRemoteTS.ps1` (line 15) to match your Task Sequence

3. **Create the scheduled tasks** with `ScheduleRemoteTS.ps1`:
   ```powershell
   .\ScheduleRemoteTS.ps1 -CsvPath ".\servers.csv" -TaskName "Invoke-FirmwareUpgrade-TS"
   ```

4. **Monitor** with `Validate-TS.ps1` after scheduling to confirm tasks are created and scripts are deployed.

---

## Troubleshooting

- **TS not found in `CCM_Program`**: Ensure the TS is deployed to a device collection and the account running the script has the deployment. Trigger machine policy refresh on the client if needed.
- **Scheduled task fails to run**: Check `Get-ScheduledTaskInfo` for the task to see `LastTaskResult`. Common issues include incorrect account, S4U restrictions, or missing script path.
- **PowerShell remoting failures**: Verify `WinRM` is enabled and the account has admin rights on target servers.
- **Password rotation impact**: The script uses S4U logon type, which does not store passwords. Password changes do not affect the scheduled task.
