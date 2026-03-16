# RalphLoop.ps1
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$StateDir,

    # Prefix for the automatically created feature branch
    [Parameter()]
    [string]$BranchPrefix = "ralph/",

    # Branch to target with the PR (defaults to the current branch at startup)
    [Parameter()]
    [string]$TargetBranch = "",

    # Azure DevOps org URL, e.g. https://dev.azure.com/myorg
    [Parameter()]
    [string]$AzureDevOpsOrg = "",

    # Azure DevOps project name
    [Parameter()]
    [string]$AzureDevOpsProject = ""
)
$MaxIterations = 15
$SummaryLog = @()

if (-not (Test-Path $StateDir)) {
    Write-Error "No plans found in $StateDir. Run .\Initialize-Feature.ps1 first."
    exit
}

# ── Branch setup ──────────────────────────────────────────────────────────────
# Capture the working branch before we create the Ralph branch
if ([string]::IsNullOrWhiteSpace($TargetBranch)) {
    $TargetBranch = git rev-parse --abbrev-ref HEAD 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not determine current git branch. Make sure you are inside a git repository."
        exit 1
    }
}

$RalphBranch = "$BranchPrefix$(Split-Path -Leaf $StateDir)"
Write-Host "Creating Ralph branch: $RalphBranch (target: $TargetBranch)" -ForegroundColor Cyan
git checkout -b $RalphBranch
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create branch '$RalphBranch'."
    exit 1
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

# ── Push branch & create Azure DevOps PR ─────────────────────────────────────
Write-Host "`nPushing '$RalphBranch' to origin..." -ForegroundColor Cyan
git push -u origin $RalphBranch
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git push failed. Push the branch manually and create the PR yourself."
} else {
    # Build PR title from completed plans
    $completedPlans = ($SummaryLog | Where-Object { $_.Status -eq "✅" } | Select-Object -ExpandProperty Plan) -join ", "
    $prTitle = if ($completedPlans) { "Ralph: $completedPlans" } else { "Ralph automated changes" }

    # Build PR description from learnings
    $prBody = $SummaryLog | ForEach-Object {
        "### $($_.Plan) $($_.Status)`n$($_.Summary)"
    } | Out-String

    if ([string]::IsNullOrWhiteSpace($AzureDevOpsOrg) -or [string]::IsNullOrWhiteSpace($AzureDevOpsProject)) {
        Write-Host "`nSkipping automatic PR creation - provide -AzureDevOpsOrg and -AzureDevOpsProject to enable it." -ForegroundColor Yellow
        Write-Host "Branch '$RalphBranch' is ready. Create a PR manually targeting '$TargetBranch'." -ForegroundColor Yellow
    } else {
        Write-Host "Creating PR in Azure DevOps..." -ForegroundColor Cyan
        $azArgs = @(
            "repos", "pr", "create",
            "--org",            $AzureDevOpsOrg,
            "--project",        $AzureDevOpsProject,
            "--source-branch",  $RalphBranch,
            "--target-branch",  $TargetBranch,
            "--title",          $prTitle,
            "--description",    $prBody,
            "--auto-complete",  "false"
        )
        az @azArgs

        if ($LASTEXITCODE -eq 0) {
            Write-Host "PR created successfully." -ForegroundColor Green
        } else {
            Write-Warning "PR creation failed. Check that the az devops extension is installed and you are logged in (az login)."
        }
    }
}