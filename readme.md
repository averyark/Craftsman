# Craftsman Kit

A Roblox Luau framework: a lifecycle loader, entities, tags, state machines, task control and utilities.

```toml
# ember.toml
[indices]
wally = "https://github.com/UpliftGames/wally-index"

[dependencies]
Craftsman = { name = "averyark/craftsman-kit", version = "^0.9.0", index = "wally" }
```

Install it with [Ember](https://luaupm.com). Craftsman is published to the Wally index, but it requires its dependencies in Ember's layout, so the Wally CLI cannot install it.

Craftsman Kit was published as `averyark/craftsman` up to 0.9.0. Name the dependency `Craftsman` in `ember.toml`, as above, and existing `Craftsman.*` code keeps working unchanged.

## Agent skill

`skills/craftsman/` is an [Agent Skill](https://agentskills.io) that teaches coding agents (Claude Code, Codex, Cursor and others) which Craftsman module to use and how to call it. It is not part of the published package.

Install it with any of these:

- **Claude Code:** `/plugin marketplace add averyark/craftsman-kit`, then `/plugin install craftsman@craftsman`
- **Any agent, via the skills CLI:** `npx skills add averyark/craftsman-kit`
- **Manually:** copy `skills/craftsman` into `.claude/skills/` (Claude Code) or `.agents/skills/` (Codex and others). For claude.ai, zip the folder and upload it under Settings → Capabilities → Skills.
