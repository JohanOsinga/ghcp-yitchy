# RalphLoop.ps1
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$StateDir
)
$MaxIterations = 15
$SummaryLog = @()

if (-not (Test-Path $StateDir)) {
    Write-Error "No plans found in $StateDir. Run .\Initialize-Feature.ps1 first."
    exit
}

$stateFiles = Get-ChildItem -Path "$StateDir" -Filter "*.json"

foreach ($file in $stateFiles) {
    Write-Host "Working on: $($file.Name)" -ForegroundColor Cyan
    $lastIndex = -1
    $stuckCount = 0

    for ($i = 1; $i -le $MaxIterations; $i++) {
        $state = Get-Content $file.FullName -Raw | ConvertFrom-Json
        
        if ($state.completed) {
            Write-Host "Plan already marked complete." -ForegroundColor Green
            break
        }

        if ($state.current_step_index -eq $lastIndex) { $stuckCount++ } else { $stuckCount = 0 }
        if ($stuckCount -gt 2) {
            Write-Host "Agent is stuck. Breaking loop." -ForegroundColor Red
            break
        }

        $lastIndex = $state.current_step_index
        Write-Host "Iteration $i | Step: $($state.current_step_index)" -ForegroundColor Yellow
        
        # Write prompt to a temp file to avoid shell argument-splitting on multi-line strings
        $TempRalphPromptFile = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -Path $TempRalphPromptFile -Value "Use the ralph-worker skill. State: $(Get-Content $file.FullName -Raw)" -Encoding UTF8
            # Triggering the skill by name now that frontmatter is fixed
            copilot -p "@$TempRalphPromptFile" --autopilot --yolo --max-autopilot-continues 3
        }
        finally {
            Remove-Item -Path $TempRalphPromptFile -ErrorAction SilentlyContinue
        }

    }

    # Generate Summary for this plan
    $finalState = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $statusEmoji = if ($finalState.completed) { "✅" } else { "❌" }
    $SummaryLog += [PSCustomObject]@{
        Plan    = $file.BaseName
        Status  = "$statusEmoji"
        Steps   = "$($finalState.current_step_index)/$($finalState.total_steps)"
        Summary = ($finalState.learnings -join "; ")
    }
}

# --- Final Summary Report ---
Write-Host "`n"
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "       RALPH LOOP EXECUTION REPORT      " -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
$SummaryLog | Format-Table -AutoSize