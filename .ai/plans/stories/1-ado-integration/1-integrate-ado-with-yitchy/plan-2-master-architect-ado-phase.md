# Plan 2: Add ADO Output Phase to master-architect Skill

## Rationale

The master-architect skill needs explicit, reliable instructions for the ADO output steps
so it consistently performs them whenever ADO context is present in the prompt. Adding a
dedicated section to `SKILL.md` makes this a first-class capability of the skill rather
than relying solely on ad-hoc prompt engineering.

This also ensures that `ado-tasks.json` — the mapping file the worker loop depends on —
is always written with a consistent schema, regardless of how the planner is invoked.

## Files Affected

- `Skills/master-architect/SKILL.md`

## Steps

### Step 1 — Add `## ADO Integration (Optional)` section to SKILL.md

Insert the new section **after Phase 3 (Artifact Generation)** and **before Phase 4
(Quality Assurance)**. The section covers four sub-steps:

- **Pre-Phase**: read the work item when `WorkItemId` is present but no free-text story
  was supplied.
- **Post-Phase A**: update the User Story description with a structured planner summary.
- **Post-Phase B**: create one child ADO Task per `plan-N-*.md` file, embedding the state
  file base name in the Task description.
- **Post-Phase C**: write `ado-tasks.json` with the full Task ID → state file mapping.

## Code Snippets

Add the following block to `Skills/master-architect/SKILL.md` after Phase 3:

```markdown
## ADO Integration (Optional)

When the prompt contains ADO Context (`WorkItemId`, `Project`, `Org`), perform the
following steps **in addition to** the standard phases.

### Pre-Phase: Read Work Item
If the prompt instructs you to read a work item (no free-text Story was provided), use
`ado-wit_get_work_item` with the given `WorkItemId` and `Project`.
Extract `System.Title` and `System.Description` as the planning story input.

### Post-Phase A: Update User Story
After all plan and state files are generated, use `ado-wit_update_work_item` to update
the User Story description with a structured planner summary containing:
- A brief description of the feature being planned.
- The architectural approach and key decisions.
- A numbered list of plan steps with their short titles.

### Post-Phase B: Create Child Tasks
Use `ado-wit_add_child_work_items` to create one ADO Task per `plan-N-*.md` file as a
child of the User Story:
- **Title**: the short description of the plan step  
  (e.g. `Plan 1: Add ADO parameters to Initialize script`)
- **Description (HTML)**: include the exact line  
  `STATE_FILE: <state-file-base-name.json>`  
  (e.g. `STATE_FILE: state-1-initialize-ado-params.json`)
- Record each returned Task ID.

### Post-Phase C: Write ado-tasks.json
Write a file named `ado-tasks.json` in the **same directory** as the generated plan
files, using the following schema:

```json
{
  "workItemId": "<WorkItemId>",
  "project": "<Project>",
  "org": "<Org>",
  "taskMappings": [
    {
      "stateFile": "state-N-{desc}.json",
      "taskId": "<created-task-id>",
      "taskTitle": "Plan N: short description"
    }
  ]
}
```

This file is consumed by `Copilot-YitchyLoop.ps1` to synchronise ADO task states without
re-querying ADO at loop startup.
```

## Manual Testing Steps

1. After updating `SKILL.md`, copy it to `C:\Users\{username}\.copilot\skills\master-architect\SKILL.md`.
2. Run `Copilot-YitchyInitialize-Feature.ps1 -WorkItemId <id> -Project <proj> -Org <org>`.
3. Verify the User Story description is updated in ADO with a planner summary.
4. Verify child Tasks are created in ADO with correct titles and `STATE_FILE:` lines in their descriptions.
5. Verify `ado-tasks.json` is created in the plan directory with the correct Task ID mappings.
