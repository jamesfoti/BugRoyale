# Checks every project script against the official GDScript style guide with gdtoolkit's
# gdlint and gdformat (python -m pip install "gdtoolkit==4.*"). The settings are in gdlintrc.
#
#   powershell -ExecutionPolicy Bypass -File tools/lint.ps1        # check, exit 1 on a finding
#   powershell -ExecutionPolicy Bypass -File tools/lint.ps1 -Fix   # rewrite with gdformat first
#
# gdformat fixes indentation, spacing and line wrapping; member order and long comments or
# strings are fixed by hand. Scripts under addons/ are not ours and are left alone.
param(
	[switch]$Fix
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot

foreach ($tool in "gdlint", "gdformat") {
	if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
		Write-Host "$tool is not installed; run: python -m pip install `"gdtoolkit==4.*`""
		exit 2
	}
}

# Tracked and untracked scripts alike (a new file must pass before it is committed).
$scripts = @(
	git -C $root ls-files --cached --others --exclude-standard "*.gd" |
		Where-Object { $_ -notlike "addons/*" }
)
Push-Location $root
try {
	if ($Fix) {
		& gdformat @scripts
	} else {
		& gdformat --check @scripts
	}
	$formatExit = $LASTEXITCODE
	& gdlint @scripts
	$lintExit = $LASTEXITCODE
} finally {
	Pop-Location
}

if ($formatExit -ne 0 -or $lintExit -ne 0) {
	Write-Host "Style check FAILED (gdformat $formatExit, gdlint $lintExit)"
	exit 1
}
Write-Host "Style check passed ($($scripts.Count) scripts)."
exit 0
