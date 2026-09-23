# Craftsman

A Roblox Luau framework: a lifecycle loader, entities, tags, state machines, task control and utilities.

```toml
# ember.toml
[dependencies]
Craftsman = { name = "averyark/craftsman", version = "^0.9.0" }
```

## Agent skill

`skills/craftsman/` is an [Agent Skill](https://agentskills.io) that teaches coding agents (Claude Code, Codex, Cursor and others) which Craftsman module to use and how to call it. It is not part of the published package.

Install it with any of these:

- **Claude Code:** `/plugin marketplace add averyark/Craftsman`, then `/plugin install craftsman@craftsman`
- **Any agent, via the skills CLI:** `npx skills add averyark/Craftsman`
- **Manually:** copy `skills/craftsman` into `.claude/skills/` (Claude Code) or `.agents/skills/` (Codex and others). For claude.ai, zip the folder and upload it under Settings → Capabilities → Skills.
