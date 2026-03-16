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

if (-not [string]::IsNullOrWhiteSpace($WorkItemId)) {
    $ArchitectPrompt = @"
Use the master-architect skill.
Read the User Story from Azure DevOps work item #$WorkItemId (Project: $Project, Org: $Org) using ado-wit_get_work_item. Use its Title and Description as the story input for planning.
After generating all plan and state files, perform the ADO Output Phase as described in the master-architect skill: update the User Story description with a planner summary, create child ADO Tasks (one per plan-N-*.md file), and write ado-tasks.json in the plan directory.
ADO Context: WorkItemId=$WorkItemId, Project=$Project, Org=$Org
Stack: $Stack
"@
} else {
    $ArchitectPrompt = "Use the master-architect skill. Story: $Story, Stack: $Stack"
}

# Write prompt to a temp file to avoid shell argument-splitting on multi-line strings
$TempPromptFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -Path $TempPromptFile -Value $ArchitectPrompt -Encoding UTF8
    copilot -i "@$TempPromptFile" --model $Model --reasoning-effort $Reasoning --yolo
} finally {
    Remove-Item -Path $TempPromptFile -ErrorAction SilentlyContinue
}