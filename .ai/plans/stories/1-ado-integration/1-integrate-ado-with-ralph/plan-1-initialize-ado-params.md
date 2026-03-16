# Plan 1: Add ADO Parameters to Initialize Script

## Rationale

The Initialize script currently accepts only a free-text `$Story`. To enable ADO
integration, we add optional `-WorkItemId`, `-Project`, and `-Org` parameters. When
`-WorkItemId` is provided the prompt to master-architect is enriched with ADO context,
instructing it to read the User Story from ADO and write plan outputs back to ADO after
planning. The original `-Story` mode is fully preserved for backward compatibility.

## Files Affected

- `Copilot-Ralph/Copilot-RalphInitialize-Feature.ps1`

## Steps

### Step 1 — Add parameters and validation guard

Add three optional string parameters (`$WorkItemId`, `$Project`, `$Org`) and a guard
that exits with an error if neither `$Story` nor `$WorkItemId` is supplied.

### Step 2 — Build ADO-aware prompt when `-WorkItemId` is provided

When `$WorkItemId` is set, construct a multi-line here-string prompt that instructs the
master-architect skill to:
1. Read the User Story from ADO using `ado-wit_get_work_item`.
2. Use its title and description as the story input for planning.
3. Perform the **ADO Output Phase** (update User Story, create child Tasks, write
   `ado-tasks.json`) after all plan files are generated.

## Code Snippets

```powershell
# Copilot-RalphInitialize-Feature.ps1 — full replacement
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
    [string]$Stack = ".NET, Blazor, and the JS framework found in the project",

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

$TempPromptFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -Path $TempPromptFile -Value $ArchitectPrompt -Encoding UTF8
    copilot -i "@$TempPromptFile" --model $Model --reasoning-effort $Reasoning --yolo
} finally {
    Remove-Item -Path $TempPromptFile -ErrorAction SilentlyContinue
}
```

## Manual Testing Steps

1. Run `Copilot-RalphInitialize-Feature.ps1 -Story "Test story"` — verify existing behavior is unchanged.
2. Run `Copilot-RalphInitialize-Feature.ps1` (no arguments) — verify a clear error message is shown.
3. Run with `-WorkItemId 1234 -Project MyProject -Org https://dev.azure.com/myorg` and inspect the temp prompt file content before it is deleted (add a `Read-Host` pause if needed) — verify the ADO context is present.
