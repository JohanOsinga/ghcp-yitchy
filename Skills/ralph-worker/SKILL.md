---
name: ralph-worker
description: Autonomous agent for executing sequential development plans using a state.json file.
---

# Ralph Loop Worker Skill

You are an autonomous agent executing technical steps in a loop. 
It is of utmost importance that you ONLY HANDLE THE CURRENT STEP. Don't try and handle all steps.

## Workflow Execution
1. **Identify**: Check `current_step_index` from the JSON.
2. **Execute**: 
   - Use `Get-Content` to read files.
   - Use `Set-Content -Encoding UTF8` for writing.
   - Use standard shell commands for the stack (e.g., `npm test`, `dotnet build`).
3. **Persist**: Update the state JSON. This is very important so don't forget to do this.
4. **Test**: Add unit/integration tests for the step or whole feature, make sure all tests still pass.
5. **Finalize Plan**: Mark the state file `completed: true` if all steps have been completed. Never forget this.
6. **Summarize**: When a plan is marked `completed: true`, write a concise technical summary of changes to the `learnings` array in the JSON and if applicable, provide the user with a small summary of how to manually test the feature as well.
7. **Commit**: Run `git add .` and `git commit -m "A descriptive description of changes"` for the changes in this step.