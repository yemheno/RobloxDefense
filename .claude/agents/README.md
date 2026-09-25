# Project subagents

Personas adapted from [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents) at commit `053ddbb` (MIT).
The frontmatter was converted to Claude Code format (kebab-case `name`, read-only `tools`), and each file gets a "RobloxDefense project mode" section.
Claude Code loads these at session start, so they're available as `subagent_type` values in any new session opened on this repo.
