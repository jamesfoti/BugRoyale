# Runs the style check (tools/lint.ps1), the unit tests (GUT, test/unit) headless, and with
# -Smoke one bot match per mode as well. Exits non-zero when anything fails, so a release
# script can gate on it.
#
#   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 [-Smoke] [-SkipLint] [-Godot <path>]
#
# The Godot console executable comes from -Godot, else the GODOT environment variable, else
# the editor installed beside the project (C:\Dev\Godot_v4.7.2-stable_win64), else "godot"
# on the PATH. -SkipLint is for a machine without Python; the style check needs gdtoolkit.
param(
	[switch]$Smoke,
	[switch]$SkipLint,
	[string]$Godot = ""
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Godot) { $Godot = $env:GODOT }
if (-not $Godot) {
	$sibling = Join-Path (Split-Path -Parent $root) "Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe"
	if (Test-Path $sibling) { $Godot = $sibling }
}
if (-not $Godot) { $Godot = "godot" }

$lintExit = 0
if (-not $SkipLint) {
	Write-Host "== Style (gdlint, gdformat)"
	& (Join-Path $PSScriptRoot "lint.ps1")
	$lintExit = $LASTEXITCODE
}

Write-Host "== Unit tests (GUT)"
& $Godot --headless --path $root -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
$unitExit = $LASTEXITCODE
if ($unitExit -ne 0) {
	Write-Host "Unit tests FAILED (exit $unitExit)"
}

$smokeExit = 0
if ($Smoke) {
	$runs = @(
		@{ map = "battlefield"; mode = "ants_vs_ants"; frames = 600 },
		@{ map = "terrarium"; mode = "battle_royale"; frames = 600 },
		@{ map = "fishbowl"; mode = "hornets"; frames = 900 },
		@{ map = "crawlspace"; mode = "cordyceps_royale"; frames = 900 },
		@{ map = "celestial_body"; mode = "explore"; frames = 300 }
	)
	foreach ($run in $runs) {
		Write-Host ("== Smoke: {0} on {1}" -f $run.mode, $run.map)
		$output = & $Godot --headless --path $root res://tools/smoke_test.tscn -- ("map=" + $run.map) ("mode=" + $run.mode) ("frames=" + $run.frames) 2>&1
		$result = $output | Where-Object { $_ -match "^SMOKE (RESULT|FAIL|TERRAIN)" }
		$result | ForEach-Object { Write-Host $_ }
		$scriptErrors = @($output | Where-Object { $_ -match "SCRIPT ERROR" }).Count
		$failed = ($LASTEXITCODE -ne 0) -or ($scriptErrors -gt 0) -or -not ($result -match "SMOKE RESULT") -or ($result -match "moved=0 ") -or ($result -match "state_roundtrip=MISMATCH")
		if ($failed) {
			Write-Host ("Smoke FAILED: {0} on {1} (exit {2}, script errors {3})" -f $run.mode, $run.map, $LASTEXITCODE, $scriptErrors)
			$smokeExit = 1
		}
	}
}

if ($lintExit -ne 0 -or $unitExit -ne 0 -or $smokeExit -ne 0) { exit 1 }
Write-Host "All tests passed."
exit 0
