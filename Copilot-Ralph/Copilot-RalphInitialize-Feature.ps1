# Initialize-Feature.ps1
[CmdletBinding()]
param (
    [Parameter(Position=0)]
    [string]$Story = "",

    [Parameter()]
    [string]$WorkItemId = "",

    [Parameter()]
    [string]$Project = "",

    [Parameter()]
    [string]$Org = "",

    [Parameter(Position=1)]
    [string]$Stack = ".NET, Blazor, and the JS framework found in the project", # Change your default stack here

    [Parameter(Position=2)]
    [string]$Model = "claude-sonnet-4.6",

    [Parameter(Position=3)]
    [string]$Reasoning = "high"
)

if ([string]::IsNullOrWhiteSpace($Story) -and [string]::IsNullOrWhiteSpace($WorkItemId)) {
    Write-Error "Provide either -Story (free-text) or -WorkItemId (Azure DevOps work item ID)."
    exit 1
}

Write-Host "Summoning the Master Architect..." -ForegroundColor Cyan

$ArchitectPrompt = "Use the master-architect skill. Story: $Story, Stack: $Stack"

# Write prompt to a temp file to avoid shell argument-splitting on multi-line strings
$TempPromptFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -Path $TempPromptFile -Value $ArchitectPrompt -Encoding UTF8
    copilot -i "@$TempPromptFile" --model $Model --reasoning-effort $Reasoning --yolo
} finally {
    Remove-Item -Path $TempPromptFile -ErrorAction SilentlyContinue
}