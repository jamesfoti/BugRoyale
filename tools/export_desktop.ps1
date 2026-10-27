# Build the Windows and macOS exports into builds/ (the only supported platforms).
param(
	[switch]$WindowsOnly,
	[switch]$MacOSOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "godot_common.ps1")

$exportWindows = -not $MacOSOnly
$exportMacOS = -not $WindowsOnly

$requiredTemplates = @()
if ($exportWindows) {
	$requiredTemplates += "windows_release_x86_64.exe"
}
if ($exportMacOS) {
	$requiredTemplates += "macos.zip"
}

Ensure-Godot -RequiredTemplates $requiredTemplates

if ($exportWindows) {
	$windowsDir = Join-Path $ProjectRoot "builds\windows"
	$windowsExe = Join-Path $windowsDir "BugRoyale.exe"
	# The game data is embedded, so the exe is the whole game.
	Invoke-GodotExport `
		-PresetName "Windows Desktop" `
		-ExportPath $windowsExe
	Write-Host "Windows build complete: builds\windows\BugRoyale.exe"
}

if ($exportMacOS) {
	Invoke-GodotExport `
		-PresetName "macOS" `
		-ExportPath (Join-Path $ProjectRoot "builds\macos\BugRoyale.zip")
	Write-Host "macOS build complete: builds\macos\BugRoyale.zip"
}
