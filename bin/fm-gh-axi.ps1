<# Usage: fm-gh-axi.ps1 <gh-axi arguments...> #>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $GhAxiArgs
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ($env:PYTHONPATH) {
    $env:PYTHONPATH = "$Root;$env:PYTHONPATH"
} else {
    $env:PYTHONPATH = $Root
}

python -m firstmate_gui_agnostic.gh_axi --cwd (Get-Location).Path -- @GhAxiArgs
exit $LASTEXITCODE
