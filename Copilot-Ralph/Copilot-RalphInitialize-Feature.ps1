# Initialize-Feature.ps1
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Story,
    
    [Parameter(Position=1)]
    [string]$Stack = ".NET, Blazor, and the JS framework found in the project" # Change your default stack here
)

Write-Host "Summoning the Master Architect..." -ForegroundColor Cyan

$ArchitectPrompt = "Use the master-architect skill. Story: $Story, Stack: $Stack"

# Write prompt to a temp file to avoid shell argument-splitting on multi-line strings
$TempPromptFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -Path $TempPromptFile -Value $ArchitectPrompt -Encoding UTF8
    copilot -i "@$TempPromptFile"
} finally {
    Remove-Item -Path $TempPromptFile -ErrorAction SilentlyContinue
}