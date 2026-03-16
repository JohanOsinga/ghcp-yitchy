# YitchyLoop.ps1
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$StateDir,

    # Prefix for the automatically created feature branch
    [Parameter()]
    [string]$BranchPrefix = "yitchy/",

    # Branch to target with the PR (defaults to the current branch at startup)
    [Parameter()]
    [string]$TargetBranch = "",

    # Azure DevOps org URL, e.g. https://dev.azure.com/myorg
    [Parameter()]
    [string]$AzureDevOpsOrg = "",

    # Azure DevOps project name
    [Parameter()]
    [string]$AzureDevOpsProject = "",

    # When provided, the loop reads ado-tasks.json from $StateDir and
    # synchronises ADO task states throughout execution.
    [Parameter()]
    [string]$WorkItemId = "",

    [Parameter()]
    [string]$Model = "claude-sonnet-4.6",

    [Parameter()]
    [string]$Reasoning = "medium"
)
$MaxIterations = 15
$SummaryLog = @()

if (-not (Test-Path $StateDir)) {
    Write-Error "No plans found in $StateDir. Run .\Initialize-Feature.ps1 first."
    exit
}

# ── Branch setup ──────────────────────────────────────────────────────────────
# Capture the working branch before we create the Yitchy branch
if ([string]::IsNullOrWhiteSpace($TargetBranch)) {
    $TargetBranch = git rev-parse --abbrev-ref HEAD 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not determine current git branch. Make sure you are inside a git repository."
        exit 1
    }
}

$YitchyBranch = "$BranchPrefix$(Split-Path -Leaf $StateDir)"
$currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
if ($currentBranch -eq $YitchyBranch) {
    Write-Host "Already on Yitchy branch: $YitchyBranch" -ForegroundColor Green
} else {
    Write-Host "Creating Yitchy branch: $YitchyBranch (target: $TargetBranch)" -ForegroundColor Cyan
    git checkout -b $YitchyBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create branch '$YitchyBranch'."
        exit 1
    }
}

$stateFiles = Get-ChildItem -Path "$StateDir" -Filter "*.json"

# ── ADO task mapping ──────────────────────────────────────────────────────────
# Keys: state file base name (e.g. "state-1-foo.json")  Values: ADO task ID
$adoTaskMap = @{}
if (-not [string]::IsNullOrWhiteSpace($WorkItemId)) {
    $adoTasksFile = Join-Path $StateDir "ado-tasks.json"
    if (Test-Path $adoTasksFile) {
        $adoMeta = Get-Content $adoTasksFile -Raw | ConvertFrom-Json
        foreach ($m in $adoMeta.taskMappings) {
            $adoTaskMap[$m.stateFile] = $m.taskId
        }
        if ([string]::IsNullOrWhiteSpace($AzureDevOpsOrg))     { $AzureDevOpsOrg     = $adoMeta.org }
        if ([string]::IsNullOrWhiteSpace($AzureDevOpsProject)) { $AzureDevOpsProject = $adoMeta.project }
        Write-Host "Loaded $($adoTaskMap.Count) ADO task mapping(s)." -ForegroundColor Cyan
    } else {
        Write-Warning "ado-tasks.json not found in $StateDir — ADO state updates will be skipped."
    }
}

foreach ($file in $stateFiles) {
    Write-Host "Working on: $($file.Name)" -ForegroundColor Cyan

    # Set ADO task to Active before starting work on this plan
    $adoTaskId = $adoTaskMap[$file.Name]
    if ($adoTaskId) {
        Write-Host "Setting ADO Task #$adoTaskId to Active..." -ForegroundColor DarkCyan
        az boards work-item update --id $adoTaskId --state "Active" `
            --org $AzureDevOpsOrg --project $AzureDevOpsProject | Out-Null
    }

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
        $TempYitchyPromptFile = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -Path $TempYitchyPromptFile -Value "Use the yitchy-worker skill. State: $(Get-Content $file.FullName -Raw)" -Encoding UTF8
            # Triggering the skill by name now that frontmatter is fixed
            copilot -p "@$TempYitchyPromptFile" --model $Model --reasoning-effort $Reasoning --yolo --autopilot --max-autopilot-continues 3
        }
        finally {
            Remove-Item -Path $TempYitchyPromptFile -ErrorAction SilentlyContinue
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

    # Sync completion back to ADO
    if ($adoTaskId -and $finalState.completed) {
        Write-Host "Setting ADO Task #$adoTaskId to Closed..." -ForegroundColor DarkCyan
        az boards work-item update --id $adoTaskId --state "Closed" `
            --org $AzureDevOpsOrg --project $AzureDevOpsProject | Out-Null

        if ($finalState.learnings.Count -gt 0) {
            $comment = "Yitchy worker completed this task.`n`nLearnings:`n" +
                       ($finalState.learnings -join "`n")
            az boards work-item comment add --id $adoTaskId --comment $comment `
                --org $AzureDevOpsOrg --project $AzureDevOpsProject | Out-Null
            Write-Host "Posted learnings as comment on ADO Task #$adoTaskId." -ForegroundColor Green
        }
    }
}

# --- Final Summary Report ---
Write-Host "`n"
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "       YITCHY LOOP EXECUTION REPORT      " -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
$SummaryLog | Format-Table -AutoSize

# ── Push branch & create Azure DevOps PR ─────────────────────────────────────
Write-Host "`nPushing '$YitchyBranch' to origin..." -ForegroundColor Cyan
git push -u origin $YitchyBranch
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git push failed. Push the branch manually and create the PR yourself."
} else {
    # Build PR title from completed plans
    $completedPlans = ($SummaryLog | Where-Object { $_.Status -eq "✅" } | Select-Object -ExpandProperty Plan) -join ", "
    $prTitle = if ($completedPlans) { "Yitchy: $completedPlans" } else { "Yitchy automated changes" }

    # Build PR description from learnings
    $prBody = $SummaryLog | ForEach-Object {
        "### $($_.Plan) $($_.Status)`n$($_.Summary)"
    } | Out-String

    if ([string]::IsNullOrWhiteSpace($AzureDevOpsOrg) -or [string]::IsNullOrWhiteSpace($AzureDevOpsProject)) {
        Write-Host "`nSkipping automatic PR creation - provide -AzureDevOpsOrg and -AzureDevOpsProject to enable it." -ForegroundColor Yellow
        Write-Host "Branch '$YitchyBranch' is ready. Create a PR manually targeting '$TargetBranch'." -ForegroundColor Yellow
    } else {
        Write-Host "Creating PR in Azure DevOps..." -ForegroundColor Cyan
        $azArgs = @(
            "repos", "pr", "create",
            "--org",            $AzureDevOpsOrg,
            "--project",        $AzureDevOpsProject,
            "--source-branch",  $YitchyBranch,
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