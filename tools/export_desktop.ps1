# Build Windows and macOS desktop exports.
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
	$windowsZip = Join-Path $windowsDir "BugRoyale.zip"
	Invoke-GodotExport `
		-PresetName "Windows Desktop" `
		-ExportPath $windowsExe
	if (Test-Path $windowsZip) {
		Remove-Item $windowsZip -Force
	}
	Compress-Archive -Path $windowsExe -DestinationPath $windowsZip -CompressionLevel Optimal
	Write-Host "Windows build complete: builds\windows\BugRoyale.exe"
	Write-Host "Windows zip for GitHub: builds\windows\BugRoyale.zip"
}

if ($exportMacOS) {
	Invoke-GodotExport `
		-PresetName "macOS" `
		-ExportPath (Join-Path $ProjectRoot "builds\macos\BugRoyale.zip")
	Write-Host "macOS build complete: builds\macos\BugRoyale.zip"
}
