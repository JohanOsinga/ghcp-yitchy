# Plan 4: Final Verification

## Rationale

Validates the complete end-to-end ADO-integrated YITCHY flow and confirms no regressions
in the existing `$Story`-based path. Because this is a PowerShell-only change (no .NET
project), "build" verification takes the form of PowerShell syntax parsing. The
end-to-end manual test covers the full happy path through both scripts.

## Files Affected

None (verification and testing only).

## Steps

### Step 1 — Validate PowerShell script syntax

Parse both modified scripts using the PowerShell AST parser to catch any syntax errors
without executing them.

### Step 2 — End-to-end ADO integration test

Walk through the full ADO-integrated flow against a real or sandbox ADO project.

### Step 3 — Regression check: original `$Story` mode

Confirm the non-ADO path still works as before by running a quick dry-run with `-Story`.

## Code Snippets

```powershell
# Step 1: Syntax validation (run from repo root)
$scripts = @(
    "Copilot-Yitchy\Copilot-YitchyInitialize-Feature.ps1",
    "Copilot-Yitchy\Copilot-YitchyLoop.ps1"
)

foreach ($script in $scripts) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $script).Path,
        [ref]$null,
        [ref]$errors
    )
    if ($errors.Count -eq 0) {
        Write-Host "✅ $script — syntax OK" -ForegroundColor Green
    } else {
        Write-Host "❌ $script — $($errors.Count) error(s):" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
    }
}
```

## Manual Testing Steps

1. **Syntax check**: run the snippet above and confirm both scripts report `✅ syntax OK`.
2. **Create a test User Story in ADO** with title `YITCHY ADO Integration Test` and a plain-text description describing a small feature.
3. **Run Initialize**: `Copilot-YitchyInitialize-Feature.ps1 -WorkItemId <id> -Project <proj> -Org https://dev.azure.com/<org>`
4. **Verify planner outputs**:
   - Plan files exist under `.ai/plans/stories/`.
   - `ado-tasks.json` exists in the plan directory.
   - User Story description in ADO now contains the planner summary.
   - Child Tasks created in ADO — one per plan file — each with a `STATE_FILE:` line.
5. **Run Loop**: `Copilot-YitchyLoop.ps1 -StateDir <path-to-plan-dir> -WorkItemId <id>`
6. **Verify loop outputs**:
   - Tasks transition **To Do → Active → Closed** in ADO as each plan executes.
   - Learnings are posted as comments on each closed Task.
   - A PR is created in ADO (if `-AzureDevOpsOrg` / `-AzureDevOpsProject` provided) referencing the branch.
7. **Regression check**: run `Copilot-YitchyInitialize-Feature.ps1 -Story "A simple test story"` — confirm plan files are created locally with no ADO output.
