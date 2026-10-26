# Clean one-shot coding (mandatory)

See `/home/box/.claude/CLAUDE.md` and `/home/box/agent-data/workflows/clean-one-shot-coding/SKILL.md`.

Default for every coding/refactor/port task: finish the new authority completely, then delete the old business path and wire callers. No feature flags, dual-write, soft fallbacks, or leftover duplicate methods for “mid-step usability” unless the user explicitly asked to ship stepwise.

Task splits must be by clear done states and git-reverts, not so every intermediate step stays product-usable. Wire for “usable” only at the end of the whole task.
