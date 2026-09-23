#Requires -Version 5.1
<#
.SYNOPSIS
	Type-checks src and test in strict mode under Luau's new type solver.

.DESCRIPTION
	Regenerates sourcemap.json from test.project.json, fetches the Roblox type definitions on
	first run, and runs `luau-lsp analyze`. Fails when luau-lsp reports any diagnostic, lint
	warnings included. rojo and luau-lsp resolve through Rokit, so run `rokit install` once
	beforehand.

.PARAMETER Refresh
	Download the Roblox type definitions again instead of reusing the cached copy.
#>
param(
	[switch]$Refresh
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$DefinitionsUrl = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau"
$CacheDirectory = Join-Path ([IO.Path]::GetTempPath()) "craftsman-analyze"
$Definitions = Join-Path $CacheDirectory "globalTypes.None.d.luau"
$DiagnosticPattern = '\(\d+,\d+\): \w+: '

Push-Location $Root

try {
	if ($Refresh -or -not (Test-Path $Definitions)) {
		New-Item -ItemType Directory -Force -Path $CacheDirectory | Out-Null
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		Invoke-WebRequest -UseBasicParsing -Uri $DefinitionsUrl -OutFile $Definitions
	}

	rojo sourcemap test.project.json --output sourcemap.json

	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}

	$ErrorActionPreference = "Continue"

	$Output = & luau-lsp analyze `
		--platform=roblox `
		--sourcemap=sourcemap.json `
		"--definitions=@roblox=$Definitions" `
		--flag:LuauSolverV2=true `
		"--ignore=**/packages/**" `
		src test 2>&1 | ForEach-Object { "$_" }

	$ExitCode = $LASTEXITCODE
	$ErrorActionPreference = "Stop"

	$Output | Where-Object { $_ -notmatch '^\[(INFO|WARN)\]' } | ForEach-Object { Write-Host $_ }

	$Diagnostics = @($Output | Where-Object { $_ -match $DiagnosticPattern } | Select-Object -Unique)

	if ($ExitCode -ne 0 -or $Diagnostics.Count -gt 0) {
		Write-Host "$($Diagnostics.Count) unique diagnostic(s)."
		exit 1
	}

	Write-Host "No diagnostics."
	exit 0
}
finally {
	Pop-Location
}
