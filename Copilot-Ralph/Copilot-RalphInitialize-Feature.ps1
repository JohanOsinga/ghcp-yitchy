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
# I am starting a new feature: '$Story'
# The technical stack is: $Stack

# ACT AS THE MASTER ARCHITECT:
# 1. Interview me: Ask any clarifying questions to resolve ambiguity.
# 2. Analyze: Look at the existing codebase to ensure the plan follows local patterns.
# 3. Structure: Create a './.plans/plan-title' directory.
# 4. Output: Generate a sequence of 'plan-N-{description}.md' and 'state-N-{description}.json' files, these MUST be sorted alphabetically so another script can run through them sequentially.
#    - Also add a singular 'summary' plan which includes the user request, and whatever decisions were made and why.
#    - Plans must be granular (max 3-4 files changed per plan).
#    - Provide code examples where applicable.
#    - Each state-N.json MUST follow this exact schema:
#      {
#        "plan_file": "plan-N.md",
#        "current_step_index": 0,
#        "total_steps": 0,
#        "completed": false,
#        "learnings": [],
#        "manual_testing_steps": null,
#      }
# 5. A final plan file should always be added which ensures that the project still builds, any unit/integration tests for the new changes were added, and that all tests still pass.
# 6. Wait for my confirmation before finalizing the files.
# "@

# Write prompt to a temp file to avoid shell argument-splitting on multi-line strings
$TempPromptFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -Path $TempPromptFile -Value $ArchitectPrompt -Encoding UTF8
    copilot -i "@$TempPromptFile"
} finally {
    Remove-Item -Path $TempPromptFile -ErrorAction SilentlyContinue
}