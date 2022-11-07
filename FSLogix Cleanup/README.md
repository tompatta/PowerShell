# FSLogix Cleanup

Will automatically clean up stale FSLogix container folders based on the specified criteria.

## Syntax

```powershell
".\FSLogix Cleanup.ps1" 
    -ContainerPath <string>
    [-DeleteRemoved]
    [-DeleteDisabled]
    [-DeleteInactive]
    [-ExcludeFolders <array>]
    [-InactiveDays <int>]
    [-NoFlipFlop]
    [-LogName <string>]
    [-LogPath <string>]
    [-Confirm]
    [-Whatif]
```

## Options

### -ContainerPath <string>

The full (UNC) path to the FSLogix container directory.

```powershell
-Containerpath "\\mystorageaccount.file.core.windows.net\share"
```

### [-DeleteRemoved]

If set, containers belonging to removed/non-existing users will be deleted.

### [-DeleteDisabled]

If set, containers belonging to disabled users will be deleted.

### [-DeleteInactive]

If set, containers belonging to inactive users will be deleted.

### [-ExcludeFolders <array>]

Array of strings with folder names to exclude in recursion.

```powershell
-ExcludeFolders @("folder1","folder2")
```

### [-InactiveDays <int>]

Number of days a user must have not logged into Active Directory to be considered inactive. Defaults to 90 days if not specified.

```powershell
-InactiveDays 180
```

### [-LogName]

Name that appears in the name of the log file. Defaults to 'FSLogixCleanUp'.

### [-LogPath]

If set to a full (UNC) path, the script will output the log file to this directory.

### [-NoFlipFlop]

If set, don't use the FlipFlop name convention (%username%\_%sid%) but use the default (%sid%\_%username%).

### [-Confirm]

If set, don't ask for confirmation before execution.

### [-Whatif]

If set, enables dry-run mode.
