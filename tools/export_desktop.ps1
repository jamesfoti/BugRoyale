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

# The terrain is a GDExtension (native/): each platform ships its compiled library, which the
# export copies beside the game. A platform without one would start with no ground at all.
$windowsLibrary = Join-Path $ProjectRoot "bin\libterrain.windows.template_release.x86_64.dll"
$macLibrary = Join-Path $ProjectRoot "bin\libterrain.macos.template_release.framework"
if ($exportWindows -and -not (Test-Path $windowsLibrary)) {
	throw "The terrain extension has no Windows release build. Build it: cd native; python -m SCons target=template_release (README, Terrain extension)."
}
if ($exportMacOS -and -not (Test-Path $macLibrary)) {
	throw "The terrain extension has no macOS build (bin\libterrain.macos.template_release.framework). Build it on a Mac (README, Terrain extension), or pass -WindowsOnly."
}

Ensure-Godot -RequiredTemplates $requiredTemplates

if ($exportWindows) {
	$windowsDir = Join-Path $ProjectRoot "builds\windows"
	$windowsExe = Join-Path $windowsDir "BugRoyale.exe"
	# The game data is embedded in the exe; the terrain extension's DLL goes beside it.
	Invoke-GodotExport `
		-PresetName "Windows Desktop" `
		-ExportPath $windowsExe
	Write-Host "Windows build complete: builds\windows\BugRoyale.exe (with its terrain DLL)"
}

if ($exportMacOS) {
	Invoke-GodotExport `
		-PresetName "macOS" `
		-ExportPath (Join-Path $ProjectRoot "builds\macos\BugRoyale.zip")
	Write-Host "macOS build complete: builds\macos\BugRoyale.zip"
}
