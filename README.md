# Skills
These should be placed at `C:\Users\{username}\.copilot\skills`

## Available Skills

### master-architect
Designs features for a .NET-based technical stack. Interviews the user, produces plan files and state files, and optionally creates ADO child Tasks.

### yitchy-worker
Autonomous agent that executes a single step from a `state-N-*.json` plan file. Driven by `Copilot-YitchyLoop.ps1`.

### ado-exec
**Standalone** autonomous execution agent. Given an ADO work item number (UserStory, Task, or Bug), it:
1. Infers ADO org/project from the git remote URL
2. Reads the work item and all child Tasks/Bugs
3. Resolves task dependencies (`Depends on: #XXXX` in description)
4. Executes each task in order — writing code from the task's description/AC
5. Auto-detects build system (dotnet / npm / pytest / make) and verifies after each task
6. Commits once per task, retries once on build/test failure
7. Pushes the feature branch and creates a PR targeting the original branch
8. Keeps all ADO work items updated (New → Active → Closed) with comments throughout

**Usage:** `Use the ado-exec skill. Work item: 1234`

# Copilot-Yitchy
These are helper scripts which should be invoked using the command line in your project. Add the folder to your PATH.
