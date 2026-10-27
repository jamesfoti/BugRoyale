# Build both platforms and publish them as a GitHub release.
#
# The version comes from config/version in project.godot. The release is tagged v<version> on
# the current commit, and the Windows exe and the macOS app zip are attached as assets, so the
# game can be downloaded straight from the Releases page.
#
# Needs the GitHub CLI (gh) signed in, and a clean, pushed working tree.
param(
	# Re-upload assets to a release that already exists for this version.
	[switch]$Overwrite,
	# Skip the export and release whatever is in builds/ already.
	[switch]$SkipBuild,
	# Release notes; the default is the commit subject.
	[string]$Notes = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Windows PowerShell 5.1 turns anything a native command writes to stderr into a terminating
# error under "Stop", even when the command succeeded (git warnings, gh's "not found"). Native
# calls run through here and are judged by their exit code instead.
function Invoke-Native {
	param([scriptblock]$Command)
	$previous = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try {
		& $Command 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
	} finally {
		$ErrorActionPreference = $previous
	}
}

$projectFile = Get-Content (Join-Path $ProjectRoot "project.godot")
$versionLine = $projectFile | Where-Object { $_ -match '^config/version="(.+)"$' } | Select-Object -First 1
if (-not $versionLine) {
	throw "project.godot has no config/version; add one under [application]."
}
$version = $Matches[1]
$tag = "v$version"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
	throw "The GitHub CLI (gh) is not installed: https://cli.github.com/"
}
$login = Invoke-Native { gh api user -q .login }
if ($LASTEXITCODE -ne 0 -or -not $login) {
	throw "gh is not signed in; run 'gh auth login' first."
}

Push-Location $ProjectRoot
try {
	$dirty = Invoke-Native { git status --porcelain }
	if ($dirty) {
		throw "Commit or stash your changes first; the release tags the current commit."
	}
	$unpushed = Invoke-Native { git log --oneline "@{u}..HEAD" }
	if ($unpushed) {
		throw "Push the current branch first; the release tags the current commit."
	}

	if (-not $SkipBuild) {
		& (Join-Path $PSScriptRoot "export_desktop.ps1")
	}

	$assets = @(
		(Join-Path $ProjectRoot "builds\windows\BugRoyale.exe"),
		(Join-Path $ProjectRoot "builds\macos\BugRoyale.zip")
	)
	foreach ($asset in $assets) {
		if (-not (Test-Path $asset)) {
			throw "Missing build output: $asset"
		}
	}
	# Assets are staged under versioned, platform-specific filenames.
	$staging = Join-Path $env:TEMP "BugRoyale-release-$version"
	if (Test-Path $staging) {
		Remove-Item -Path $staging -Recurse -Force
	}
	New-Item -ItemType Directory -Force -Path $staging | Out-Null
	$labelled = @(
		(Join-Path $staging "BugRoyale-$version-windows.exe"),
		(Join-Path $staging "BugRoyale-$version-macos.zip")
	)
	for ($index = 0; $index -lt $assets.Count; $index++) {
		Copy-Item -Path $assets[$index] -Destination $labelled[$index] -Force
	}

	if (-not $Notes) {
		$Notes = git log -1 --pretty=%s
	}

	$existingTags = @(Invoke-Native { gh release list --json tagName -q ".[].tagName" })
	$exists = $existingTags -contains $tag
	if ($exists -and -not $Overwrite) {
		throw "Release $tag already exists. Bump config/version in project.godot, or pass -Overwrite to replace its assets."
	}
	if ($exists) {
		Write-Host "Replacing assets on release $tag ..."
		Invoke-Native { gh release upload $tag $labelled --clobber }
	} else {
		Write-Host "Creating release $tag ..."
		Invoke-Native { gh release create $tag $labelled --title "BugRoyale $version" --notes $Notes }
	}
	if ($LASTEXITCODE -ne 0) {
		throw "gh release failed."
	}
	Remove-Item -Path $staging -Recurse -Force
	$url = Invoke-Native { gh release view $tag --json url -q .url }
	Write-Host "Published: $url"
} finally {
	Pop-Location
}
