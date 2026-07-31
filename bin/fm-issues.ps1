param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $IssueOpsArgs
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ($env:PYTHONPATH) {
    $env:PYTHONPATH = "$Root;$env:PYTHONPATH"
} else {
    $env:PYTHONPATH = $Root
}

python -m firstmate_gui_agnostic.issueops @IssueOpsArgs
exit $LASTEXITCODE
