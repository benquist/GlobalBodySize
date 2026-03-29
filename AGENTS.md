# Workspace Agent Policy

## Mandatory Final Gate
Before returning any result to the user, run the always agent as the final pre-return check.

## Required Pass Condition
Do not return to the user unless always reports PASS.

## Always Agent Scope
The always agent must verify all of the following:
- Prompt is recorded in agents/prompt_log.md
- Updated Rmd files compile successfully
- Updated R packages build successfully
- Git push status is confirmed

## Update Discipline
If the task changed agent behavior or agent files, append a new entry to:
- agents/agent_chat_provenance_log.txt
