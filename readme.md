# Craftsman Kit

A Roblox Luau framework: entities, tags, state machines, pathfinding, task control and utilities. The module loader is its own package, `averyark/craftsman-lifecycle`.

```toml
# ember.toml
[indices]
wally = "https://github.com/UpliftGames/wally-index"

[dependencies]
Craftsman = { name = "averyark/craftsman-kit", version = "^0.10.0", index = "wally" }
Lifecycle = { name = "averyark/craftsman-lifecycle", version = "^1.0.0", index = "wally" }
```

Install it with [Ember](https://luaupm.com). Craftsman is published to the Wally index, but it requires its dependencies in Ember's layout, so the Wally CLI cannot install it.

Craftsman Kit was published as `averyark/craftsman` up to 0.9.0. Name the dependency `Craftsman` in `ember.toml`, as above, and existing `Craftsman.*` code keeps working unchanged.

### Alongside Wally

`wally install` deletes `Packages/`, and on Windows and macOS that is the same folder as Ember's `packages/`. In a project that also uses Wally, install Ember elsewhere:

```toml
# ember.toml
[config]
roblox-packages-out = "ember"
```

and map both into one `Packages` in Rojo:

```json
"Packages": {
  "$path": "Packages",
  "Craftsman": { "$path": "ember/Craftsman.luau" },
  "Lifecycle": { "$path": "ember/Lifecycle.luau" },
  ".ember": { "$path": "ember/.ember" }
}
```

## Agent skill

`skills/craftsman-kit/` is an [Agent Skill](https://agentskills.io) that teaches coding agents (Claude Code, Codex, Cursor and others) which Craftsman module to use and how to call it. It is not part of the published package.

Install it with any of these:

- **Claude Code:** `/plugin marketplace add averyark/craftsman-kit`, then `/plugin install craftsman-kit@craftsman-kit`
- **Any agent, via the skills CLI:** `npx skills add averyark/craftsman-kit`
- **Manually:** copy `skills/craftsman-kit` into `.claude/skills/` (Claude Code) or `.agents/skills/` (Codex and others). For claude.ai, zip the folder and upload it under Settings → Capabilities → Skills.
