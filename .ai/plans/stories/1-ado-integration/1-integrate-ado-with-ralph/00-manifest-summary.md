# ADO Integration for RALPH — Architecture Manifest

## Overview

This feature integrates the RALPH pattern with Azure DevOps, enabling the planner
(`master-architect`) to read User Stories from ADO and output structured plans back as
ADO Tasks, and enabling the worker loop to drive ADO task state transitions in sync with
local execution state.

## Architectural Decisions

### Hybrid State Model
Local `state.json` files remain the execution engine for the worker loop — they track
sub-step progress (`current_step_index`), stuck-detection counters, and learnings. ADO
Tasks serve as a mirror for human visibility and project management. This avoids tight
coupling to ADO APIs during execution and preserves the loop's existing resilience
mechanisms unchanged.

### ADO Task → State File Mapping via `ado-tasks.json`
After planning, the master-architect writes an `ado-tasks.json` file alongside the plan
files. This maps each ADO Task ID to its corresponding local `state.json` filename. The
worker loop reads this file at startup to perform ADO state updates without needing to
re-query ADO for child work items at runtime.

### `az boards` CLI for Loop-Time ADO Updates
The worker loop uses the `az boards` Azure CLI extension for state transitions and
comments. This keeps the loop script standalone (no Copilot CLI sub-invocation needed for
ADO operations) and aligns with the existing `az` usage in the script for PR creation.

> **Prerequisite**: `az extension add --name azure-devops` must be installed and
> `az login` completed before running the loop with ADO integration.

### ADO MCP Tools for Planner-Time ADO Operations
The master-architect skill (invoked via Copilot CLI) uses the available ADO MCP tools
(`ado-wit_get_work_item`, `ado-wit_update_work_item`, `ado-wit_add_child_work_items`) for
reading the User Story and writing plan outputs back. These tools are available within a
Copilot CLI session.

## ADO Work Item Flow

```mermaid
sequenceDiagram
    participant User
    participant Init as Initialize-Feature.ps1
    participant Copilot as Copilot CLI<br/>(master-architect)
    participant ADO as Azure DevOps
    participant Loop as RalphLoop.ps1
    participant Worker as Copilot CLI<br/>(ralph-worker)

    User->>Init: -WorkItemId 1234 -Project MyProj -Org https://...
    Init->>Copilot: Prompt with ADO context
    Copilot->>ADO: ado-wit_get_work_item(1234)
    ADO-->>Copilot: User Story title + description
    Note over Copilot: Generates plan-N-*.md + state-N-*.json files
    Copilot->>ADO: ado-wit_update_work_item(1234, planner summary)
    Copilot->>ADO: ado-wit_add_child_work_items(1234, tasks[])
    ADO-->>Copilot: Created Task IDs [5678, 5679, ...]
    Copilot->>Copilot: Write ado-tasks.json (ID → state file mapping)

    User->>Loop: -StateDir <path> -WorkItemId 1234
    Loop->>Loop: Read ado-tasks.json → build taskId map
    Loop->>ADO: az boards work-item update --state Active (Task 5678)
    Loop->>Worker: copilot (state-1-xxx.json)
    Worker-->>Loop: completed=true, learnings=[...]
    Loop->>ADO: az boards work-item update --state Closed (Task 5678)
    Loop->>ADO: az boards work-item comment add (learnings)
    Note over Loop: Repeats for each remaining task
```

## ADO Task State Transitions

| Phase | ADO Task State |
|---|---|
| After planner creates task | To Do |
| Before worker begins execution | Active |
| After worker completes (`completed: true`) | Closed |
| If worker fails / stuck | Remains Active (manual intervention) |

## Files Modified

| File | Change |
|---|---|
| `Copilot-Ralph/Copilot-RalphInitialize-Feature.ps1` | Add ADO params; build ADO-aware prompt |
| `Skills/master-architect/SKILL.md` | Add ADO Integration (Optional) section |
| `Copilot-Ralph/Copilot-RalphLoop.ps1` | Read `ado-tasks.json`; update task states |

## NuGet / External Tools Added

- No NuGet packages (PowerShell-only changes)
- **Required**: Azure CLI `azure-devops` extension (`az extension add --name azure-devops`)

## Trade-offs

| Decision | Alternative Considered | Reason for Choice |
|---|---|---|
| `az boards` for loop ADO calls | ADO MCP tools via Copilot sub-invocation | Simpler, synchronous, aligns with existing `az` usage in script |
| `ado-tasks.json` mapping file | Re-query ADO at loop startup | More resilient; works offline; no extra API calls in tight loop |
| Update User Story description | Add planning summary as a comment | Keeps the description as the single source of truth for the plan |
| State files remain execution engine | ADO Tasks as sole state | Preserves stuck-detection, sub-step tracking, and loop resilience |
