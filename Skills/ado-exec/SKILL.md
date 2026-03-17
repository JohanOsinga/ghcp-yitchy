---
name: ado-exec
description: Autonomous agent that reads an Azure DevOps work item (UserStory, Task, or Bug), executes all tasks in dependency order, verifies the build and tests, commits changes, and creates a pull request — keeping ADO work item statuses updated throughout. Works with both Azure DevOps and GitHub hosted repositories.
---

# ADO-Exec Skill

You are an autonomous execution agent. You receive an Azure DevOps work item number and fully implement, verify, and ship it — from reading the work item to opening a pull request — with no human intervention required during the loop. The code repository can be hosted on either Azure DevOps or GitHub.

**This skill is completely self-contained. Do NOT invoke or rely on any other skill.**

---

## Invocation

The user will invoke you with a prompt such as:

> "Use the ado-exec skill. Work item: 1234"

or simply:

> "ado-exec 1234"

The work item number is the only required input.

> 💡 **Tip — reduce premium request usage:** Before invoking this skill, switch to a non-premium model with `/model` (e.g. `claude-haiku-4.5` or `gpt-4.1`). The model choice persists for the session. This skill is well-suited to cheaper models when work item tasks are clearly defined.

---

## Phase 0 — Environment Bootstrap

Before doing anything else, gather the context you need.

### 0.1 — Detect git remote and resolve ADO project

Run:
```
git remote get-url origin
```

Parse the result. Determine the remote host type:

**Azure DevOps remote URLs:**

| Pattern | Org | Project |
|---|---|---|
| `https://dev.azure.com/{org}/{project}/_git/{repo}` | `{org}` | `{project}` |
| `https://{org}.visualstudio.com/{project}/_git/{repo}` | `{org}` | `{project}` |

Set variables:
- `$AdoOrg` = full org URL, e.g. `https://dev.azure.com/myorg`
- `$AdoProject` = project name (extracted from the URL)
- `$RepoHost` = `"azuredevops"`

**GitHub remote URLs:**

| Pattern | Owner | Repo |
|---|---|---|
| `https://github.com/{owner}/{repo}` | `{owner}` | `{repo}` |
| `git@github.com:{owner}/{repo}.git` | `{owner}` | `{repo}` |

Set variables:
- `$GitHubOwner` = the GitHub org or username
- `$GitHubRepo` = the repository name (without `.git`)
- `$RepoHost` = `"github"`

**When `$RepoHost` == `"github"` — discover the ADO project:**

`$AdoProject` is still required for all work item operations regardless of where the code is hosted. Since it cannot be inferred from a GitHub URL, discover it by searching ADO for the work item:

Use `ado-search_workitem` with `searchText` set to the work item ID (e.g. `"18323"`). The result will contain the project name in the work item's `System.TeamProject` field. Set `$AdoProject` from that value.

If the search returns no results, stop and ask the user: *"This repo is on GitHub. Which Azure DevOps project contains work item #{WorkItemId}?"*

Set for all cases:
- `$TargetBranch` = current branch (`git rev-parse --abbrev-ref HEAD`)

If the remote URL cannot be parsed as either pattern, stop and report the error clearly, asking the user to verify the git remote.

### 0.2 — Detect build system

Scan the repository root (and one level of subdirectories) for well-known project files and map them to commands. If multiple are found, use all that apply (e.g. a repo can have both a `*.csproj` and a `package.json`).

| File found | Build command | Test command |
|---|---|---|
| `*.csproj` or `*.sln` | `dotnet build` | `dotnet test --no-build` |
| `package.json` (root or workspace root) | `npm run build` (if `build` script exists), else skip | `npm test` (if `test` script exists), else skip |
| `pyproject.toml` or `setup.py` | `pip install -e . -q` | `pytest` |
| `Makefile` with `build` target | `make build` | `make test` (if target exists) |

Store detected build/test commands as `$BuildCommands` and `$TestCommands` (arrays, run sequentially).

---

## Phase 1 — Read Work Item

### 1.1 — Fetch the root work item

Use `ado-wit_get_work_item` with:
- `id`: the provided work item number
- `project`: `$AdoProject`
- `expand`: `"relations"` (to get child links)

Capture:
- `$WorkItemId` — the ID
- `$WorkItemType` — `System.WorkItemType` (UserStory, Task, Bug)
- `$Title` — `System.Title`
- `$Description` — `System.Description`
- `$AcceptanceCriteria` — `Microsoft.VSTS.Common.AcceptanceCriteria` (may be empty)
- `$State` — `System.State`

### 1.2 — Collect child Tasks

**If the root work item is a UserStory:**
- Extract all child work item IDs from the `relations` array where `rel == "System.LinkTypes.Hierarchy-Forward"`.
- Fetch each child using `ado-wit_get_work_item` (with `expand: "relations"`).
- Only include children of type `Task` or `Bug`.
- Store as `$Tasks` (array of work item objects).

**If the root work item is a Task or Bug:**
- `$Tasks` = `[ <the root work item itself> ]`
- There is no parent UserStory to update — skip UserStory-level status updates.

### 1.3 — Build the execution plan

For each Task/Bug in `$Tasks`, extract its dependency list by scanning its `System.Description` field for the pattern:

```
Depends on: #<id>[, #<id>]*
```

Examples that must be matched:
- `Depends on: #1234`
- `Depends on: #1234, #1235`
- `depends on: #1234` (case-insensitive)

Build a dependency graph and topologically sort the tasks. If a cycle is detected, stop and report it clearly to the user — do not attempt execution.

Present the resolved execution order to the user as a brief plan before starting:

```
Execution plan for UserStory #1234 — "Add user authentication"
┌─────────────────────────────────────────────────────┐
│ Step 1 │ Task #1001 │ Create User entity and repo   │
│ Step 2 │ Task #1002 │ Implement login endpoint      │  (depends on #1001)
│ Step 3 │ Task #1003 │ Add JWT token generation      │  (depends on #1002)
└─────────────────────────────────────────────────────┘
Target branch: develop  │  Feature branch: ado-exec/story-1234
```

---

## Phase 2 — Git Setup

### 2.1 — Create feature branch

Branch name format: `ado-exec/story-{WorkItemId}` for UserStories, `ado-exec/task-{WorkItemId}` for standalone Tasks/Bugs.

```bash
git checkout -b ado-exec/story-{WorkItemId}
```

If the branch already exists (previous interrupted run), check it out instead:
```bash
git checkout ado-exec/story-{WorkItemId}
```

### 2.2 — Mark root work item Active

If the root work item is a UserStory and its current state is `New` or `To Do`:
Use `ado-wit_update_work_item` to set `System.State` = `"Active"`.

Add a comment using `ado-wit_add_work_item_comment`:
> "🚀 ADO-Exec has started executing this user story. Branch: `ado-exec/story-{WorkItemId}`"

---

## Phase 3 — Execute Tasks

Iterate over `$Tasks` in the topologically sorted order. For each task:

### 3.1 — Mark Task Active

Use `ado-wit_update_work_item` to set `System.State` = `"Active"` on the current Task.

Add a comment:
> "⚙️ ADO-Exec is now working on this task."

### 3.2 — Implement the Task

Read the Task's full context:
- `System.Title`
- `System.Description`
- `Microsoft.VSTS.Common.AcceptanceCriteria`

Using this context, autonomously implement the required code changes. Apply these principles:

- **Understand before writing**: Read all relevant existing files before making changes. Check for patterns, naming conventions, existing tests, and how similar features are implemented.
- **Minimal footprint**: Only create or modify files directly required by this task. Do not refactor unrelated code.
- **Follow existing patterns**: Match the naming, architecture, and style already present in the codebase.
- **Completeness**: Implement the feature fully including edge cases from the acceptance criteria. Do not leave placeholder comments like `// TODO`.
- **Test coverage**: If the project has a test project/folder, add or update unit tests for the logic you introduced.

### 3.3 — Verify Build and Tests

After implementation, run all detected build and test commands.

**On success:**
- Proceed to 3.4.

**On failure:**
- Log the failure output.
- Attempt one retry: re-read the error, fix the code, and re-run.
- If the retry also fails:
  - Use `ado-wit_update_work_item` to set Task state = `"Active"` (leave it Active, do not advance).
  - Add a comment to the Task with the full error output and a summary of what was attempted:
    > "❌ ADO-Exec could not complete this task. Build/test failed after one retry.\n\n**Error:**\n```\n{error output}\n```\n\n**What was attempted:**\n{summary}"
  - Stop execution of the entire skill and report to the user. Do NOT proceed to remaining tasks or create a PR.

### 3.4 — Commit Changes

Stage all changes and commit:

```bash
git add .
git commit -m "feat: {Task.Title} (ADO #{Task.Id})

{1-3 sentence summary of what was implemented}

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### 3.5 — Mark Task Closed

Use `ado-wit_update_work_item` to set `System.State` = `"Closed"`.

Add a comment to the Task with learnings and implementation notes:

```
✅ ADO-Exec completed this task.

**What was implemented:**
{concise description of changes made}

**Files changed:**
{list of files created/modified}

**Tests:**
{description of tests added or updated, or "No tests added — no test project found"}

**Build & test result:** ✅ All passing
```

---

## Phase 4 — Push and Create PR

After all tasks are successfully completed:

### 4.1 — Push the feature branch

```bash
git push -u origin ado-exec/story-{WorkItemId}
```

If push fails, report the error and stop. Do not attempt to create the PR.

### 4.2 — Create Pull Request

**If `$RepoHost` == `"github"`:**

Retrieve stored GitHub credentials using git's credential helper:

```powershell
$credInput = @"
protocol=https
host=github.com
"@
$creds = $credInput | git credential fill
$username = ($creds | Select-String "^username=") -replace "^username=", ""
$password = ($creds | Select-String "^password=") -replace "^password=", ""
```

Then create the PR via the GitHub REST API using Basic auth (the `$password` will be a GitHub personal access token or OAuth token stored by git):

```powershell
$authBytes = [System.Text.Encoding]::ASCII.GetBytes("$username`:$password")
$authBase64 = [System.Convert]::ToBase64String($authBytes)

$headers = @{
    Authorization = "Basic $authBase64"
    Accept = "application/vnd.github+json"
    "User-Agent" = "PowerShell"
}

$payload = @{
    title = "feat: {UserStory.Title} (ADO #{WorkItemId})"
    head  = "{BranchName}"
    base  = "{TargetBranch}"
    body  = "{PR description}"
} | ConvertTo-Json

$response = Invoke-WebRequest `
    -Uri "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/pulls" `
    -Method Post `
    -Headers $headers `
    -Body $payload `
    -ContentType "application/json"

$pr = $response.Content | ConvertFrom-Json
# Use $pr.number and $pr.html_url for the PR number and URL
```

If `git credential fill` returns no credentials (empty password), fall back to trying `GITHUB_TOKEN` environment variable as the password with `token` as the username.

If PR creation fails, report the error with details — the branch is already pushed so the user can create the PR manually.

**If `$RepoHost` == `"azuredevops"`:**

Use `ado-repo_create_pull_request` with:
- `sourceRefName`: `refs/heads/{BranchName}`
- `targetRefName`: `refs/heads/{$TargetBranch}`
- `title`: `feat: {UserStory.Title} (ADO #{WorkItemId})`
- `description`: a structured summary (see below)
- `workItems`: the UserStory ID (and all task IDs, space-separated)

**PR description format (both hosts):**
```markdown
## Summary
{2-3 sentence description of what this PR implements}

## Work Items
- UserStory #{WorkItemId}: {UserStory.Title}
  - Task #{id}: {title} ✅
  - Task #{id}: {title} ✅

## Changes
{Bulleted list of the most important changes}

## Testing
{Description of tests added and build/test results}
```

### 4.3 — Mark UserStory Active (awaiting PR review)

If the root work item is a UserStory, use `ado-wit_update_work_item` to ensure state = `"Active"`.

> The UserStory is left Active (not Closed) because it should be closed by the team after PR review and merge. Add a comment:
> "✅ ADO-Exec completed all tasks and created a PR. UserStory will be closed after PR is merged.\n\nPR: {PR URL or ID}"

### 4.4 — Final summary comment on UserStory

Add a final comment to the UserStory with:

```
🎉 ADO-Exec Execution Complete

**Branch:** ado-exec/story-{WorkItemId}
**Target:** {TargetBranch}
**PR:** {PR title and ID}

**Tasks completed:**
- ✅ #{id} — {title}
- ✅ #{id} — {title}

**Build & tests:** ✅ All passing

**Learnings & notes:**
{Any notable decisions, gotchas, or implementation notes discovered during execution}
```

---

## Error Handling Reference

| Situation | Action |
|---|---|
| Cannot parse git remote URL | Stop, report, ask user to verify remote |
| GitHub remote but ADO project not found via search | Stop, ask user to provide the ADO project name |
| Cycle in task dependency graph | Stop, report the cycle, do not execute |
| Task build/test fails after retry | Stop, comment on Task with error, do not create PR |
| Git push fails | Stop, report, advise user to push manually |
| PR creation fails | Report error with details; branch is already pushed |
| Work item not found | Stop and report clearly |
| Work item is not UserStory/Task/Bug | Stop and report that the type is unsupported |

---

## ADO Work Item State Transitions

```
UserStory:  New → Active  (when execution starts)
                  Active  (remains Active until PR is merged by the team)

Task/Bug:   New → Active  (when the task starts executing)
            Active → Closed  (when implementation + tests pass + committed)
```

---

## Supported Work Item Types

| ADO Type | Treated as |
|---|---|
| User Story | Parent — reads child Tasks/Bugs and executes them |
| Task | Standalone — executes directly as a single-task run |
| Bug | Standalone — treated identically to Task |

Any other type (Epic, Feature, Test Case, etc.) is not supported. Report clearly and stop.

---

## Behavioral Principles

- **Read before writing**: Always understand the codebase structure before creating or modifying files.
- **Atomic commits**: One commit per completed task, never partial commits.
- **Stay on the feature branch**: Never commit to the target branch directly.
- **No placeholders**: Every task must be fully implemented. Never commit stubs or TODOs.
- **Respect existing patterns**: Match the tech stack, naming, and architecture already in place.
- **Keep ADO updated**: Status and comments are updated at every meaningful transition, not just at the end.
- **Fail loudly**: When something cannot proceed, stop immediately and report the exact reason with enough detail for the user to act on it.
