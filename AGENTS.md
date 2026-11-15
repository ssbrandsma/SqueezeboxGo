# AGENTS.md — Squeezebox RG35XX H

Project Lead (Agent 0) owns architecture, interface contracts, ADRs,
integration branch, and release readiness.

## Agent ownership

- Agent 1 Platform: `platform/`, `build/image/`, `build/docker/`
- Agent 2 Core: `squeezeplay/`, `build/toolchain/`
- Agent 3 Audio: `audio/`, `squeezeplay/patches/` (audio only, coordinate with Agent 2)
- Agent 4 UI: `ui/`, splash + input mapping
- Agent 5 Standalone: `standalone/`
- Agent 6 QA: `tests/`, `scripts/`, `docs/test-results/`, `releases/`

Shared contracts: `docs/interface-contracts.md` (Lead approval required to change).

## Rules

- Work in your own branch; write-capable parallel work uses isolated git worktrees.
- One common build contract: see `docs/build.md`. No private toolchains.
- Never edit another agent's owned tree without coordination + note in commit.
- Small reviewable patches against upstream; never commit upstream trees wholesale.
- No secrets, images, or build caches in git. No flashing block devices.
- Commit messages: `[area] short description` (areas: platform, core, audio, ui, standalone, qa, docs).
- Update `docs/project-status.md` at milestones. Claims need evidence in `docs/test-results/`.
- Full autonomy mandate applies: decide routine technical questions, document, continue.
