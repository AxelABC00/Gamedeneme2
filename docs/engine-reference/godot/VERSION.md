# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.3 |
| **Project Pinned** | 2026-06-29 |
| **LLM Knowledge Cutoff** | May 2025 |
| **Risk Level** | LOW — version is within LLM training data (cutoff ~4.3) |

## Note

This project is intentionally pinned to **Godot 4.3**, which is within the LLM's
training data. The model knows 4.3's API well, so the risk of hallucinated or
deprecated API suggestions is low. Engine reference docs are therefore optional
for 4.3.

Newer releases exist (4.4, 4.5, 4.6). The sibling files in this directory
(`breaking-changes.md`, `deprecated-apis.md`, `current-best-practices.md`,
`modules/`) describe changes introduced in **4.4 → 4.6** and are **not relevant
while pinned to 4.3** — treat them as upgrade reference only. If/when we upgrade,
run `/setup-engine upgrade 4.3 <new-version>` and they become authoritative again.

Run `/setup-engine refresh` to repopulate 4.3-specific docs if agents ever
suggest incorrect APIs.

## Verified Sources

- Official 4.3 docs: https://docs.godotengine.org/en/4.3/
- 4.3 release notes: https://godotengine.org/releases/4.3/
