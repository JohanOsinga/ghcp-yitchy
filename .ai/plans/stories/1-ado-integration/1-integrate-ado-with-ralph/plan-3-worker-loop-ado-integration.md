# Plan 3: Add ADO State Management to Worker Loop Script

## Rationale

The loop script currently operates entirely with local state files. To close the ADO
integration loop, the script must update ADO task states (To Do → Active → Closed) and
post learnings as comments when a plan completes.

Using `az boards` CLI (from the Azure CLI `azure-devops` extension) keeps this
standalone: no Copilot CLI sub-invocation is needed for these operations, and the
approach aligns with the existing `az` usage already present in the script for PR
creation. Graceful degradation is built in — if `ado-tasks.json` is absent or
`-WorkItemId` is not supplied, the script runs exactly as before.

## Files Affected

- `Copilot-Ralph/Copilot-RalphLoop.ps1`

## Steps

### Step 1 — Add ADO parameters and load `ado-tasks.json`

Add optional `-WorkItemId` parameter (the worker loop does not need `-Project` / `-Org`
separately — it reads those from `ado-tasks.json` if present, with the existing
`-AzureDevOpsOrg` / `-AzureDevOpsProject` parameters as overrides). After the state
files are located, attempt to load `ado-tasks.json` from `$StateDir` and build an
in-memory hashtable keyed by state file base name.

### Step 2 — Before each plan: set ADO Task to "Active"

Immediately before entering the inner execution loop for a state file, look up the task
ID in the hashtable and call `az boards work-item update --state Active`.

### Step 3 — After each plan: set ADO Task to "Closed" and post learnings comment

After the inner loop finishes, if the final state has `completed = true`, call
`az boards work-item update --state Closed` and then post the learnings array as a
comment with `az boards work-item comment add`.

## Code Snippets

### Step 1 — New parameter and ado-tasks.json loading

```powershell
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$StateDir,

    [Parameter()]
    [string]$BranchPrefix = "ralph/",

    [Parameter()]
    [string]$TargetBranch = "",

    [Parameter()]
    [string]$AzureDevOpsOrg = "",

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

# ... (existing $MaxIterations, $SummaryLog, branch setup unchanged) ...

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
```

### Step 2 — Set Active before worker (inside foreach loop, before inner for)

```powershell
foreach ($file in $stateFiles) {
    Write-Host "Working on: $($file.Name)" -ForegroundColor Cyan

    # Set ADO task to Active
    $adoTaskId = $adoTaskMap[$file.Name]
    if ($adoTaskId) {
        Write-Host "Setting ADO Task #$adoTaskId to Active..." -ForegroundColor DarkCyan
        az boards work-item update --id $adoTaskId --state "Active" `
            --org $AzureDevOpsOrg --project $AzureDevOpsProject | Out-Null
    }

    $lastIndex = -1
    $stuckCount = 0
    # ... existing inner for loop unchanged ...
}
```

### Step 3 — Set Closed + add comment after worker (inside foreach, after inner for)

```powershell
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
            $comment = "Ralph worker completed this task.`n`nLearnings:`n" +
                       ($finalState.learnings -join "`n")
            az boards work-item comment add --id $adoTaskId --comment $comment `
                --org $AzureDevOpsOrg --project $AzureDevOpsProject | Out-Null
            Write-Host "Posted learnings as comment on ADO Task #$adoTaskId." -ForegroundColor Green
        }
    }
```

## Manual Testing Steps

1. Run the loop **without** `-WorkItemId` — verify existing behavior is completely unchanged.
2. Run with a valid `ado-tasks.json` and `-WorkItemId` — verify each task transitions **Active** at the start of its plan and **Closed** at the end.
3. Verify learnings appear as comments on each completed ADO Task.
4. Introduce a stuck-loop scenario (state never advances) — verify the task remains **Active** and does not get set to **Closed**.
