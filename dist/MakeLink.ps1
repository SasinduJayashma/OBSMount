# MakeLink.ps1
param(
    [Parameter(Mandatory=$true)][string]$LinkPath,
    [Parameter(Mandatory=$true)][string]$TargetPath,
    [string]$Arguments = "",
    [string]$WorkingDirectory = "",
    [string]$IconLocation = "",
    [int]$IconIndex = 0,
    [int]$WindowStyle = 1, # 1 = Normal, 3 = Maximized, 7 = Minimized/NoActivate
    [string]$Description = ""
)

try {
    $LinkDir = Split-Path -Path $LinkPath -Parent
    if (-not (Test-Path $LinkDir)) {
        New-Item -ItemType Directory -Path $LinkDir -Force | Out-Null
    }

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($LinkPath)
    $Shortcut.TargetPath = $TargetPath
    if ($Arguments -ne "") { $Shortcut.Arguments = $Arguments }
    if ($WorkingDirectory -ne "") { $Shortcut.WorkingDirectory = $WorkingDirectory }
    if ($IconLocation -ne "") { $Shortcut.IconLocation = "$IconLocation,$IconIndex" }
    if ($Description -ne "") { $Shortcut.Description = $Description }
    $Shortcut.WindowStyle = $WindowStyle
    $Shortcut.Save()
    # You can add Write-Host lines here for logging if you run it with a visible console during testing.
    exit 0 # Success
}
catch {
    Write-Error "Error creating shortcut: $($_.Exception.Message)"
    exit 1 # Failure
}