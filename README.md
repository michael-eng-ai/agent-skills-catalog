# Agent Skills Catalog

A catalog of public skills and installers for AI coding agents (Claude Code, Codex, Cursor and others), focused on data engineering and software development, with one extra column most lists leave out: **which agent folders each one writes to**.

Several of these tools configure every agent they detect on the machine, default to Claude Code paths, or contain instructions that tell the agent to create Claude files. The result is that `.claude/` or `CLAUDE.md` can appear in a project where a different agent was being used. This catalog documents that behavior with a pointer to the upstream source for every entry.

Nothing here is redistributed. Every entry links to its upstream repository; install from there.

- Sources read on: 2026-11-18
- Line numbers refer to the upstream default branch on that date and will drift. Pin a commit if you need a stable reference.
- Not affiliated with any of the projects listed.

## How Claude files end up in a non-Claude project

| Mechanism | What happens |
|---|---|
| M1. Detect-all installer | The installer looks for every agent on the machine and configures all of them |
| M2. Claude is the default target | With no flag, the installer writes to `.claude/` |
| M3. The skill text says so | `SKILL.md` or a bundled script instructs the agent to create a Claude file, whichever agent runs it |
| M4. The framework generates it | A framework writes `CLAUDE.md` on its own when it detects a coding agent |

## Catalog

### Installers and CLIs

| Tool | Upstream | Install | Writes to | Mechanism | Source |
|---|---|---|---|---|---|
| Skills CLI | [vercel-labs/skills](https://github.com/vercel-labs/skills) | `npx skills add <owner/repo>` | `.agents/skills/` (Codex and most agents), `.claude/skills/` (Claude Code), `skills-lock.json`; project scope by default; `--all` targets every agent | M1 | `docs/agents.md` L17, L19, L88; `docs/commands.md` L78, L131 |
| Databricks CLI AI tools | [databricks/databricks-agent-skills](https://github.com/databricks/databricks-agent-skills) | `databricks aitools install` | Installs the plugin through each detected agent's own CLI; raw skills under `.databricks/aitools/skills/`; with project scope also `.claude/settings.json` | M1 | `databricks aitools install --help`; [CLI reference](https://docs.databricks.com/aws/en/dev-tools/cli/reference/aitools-commands) |
| Databricks AI Dev Kit | [databricks-solutions/ai-dev-kit](https://github.com/databricks-solutions/ai-dev-kit) | see upstream `install.sh` | Project scope by default; turns Claude on when the `claude` command exists; manages `.claude/`, `.mcp.json` and other agent folders | M1 | `install.sh` L1113-L1160; `README.md` L161, L165 |
| Firecrawl CLI | [firecrawl/cli](https://github.com/firecrawl/cli) | `npx -y firecrawl-cli@latest init` | Shared `~/.agents/skills` plus every detected agent | M1 | `README.md` L14-L60 |
| dbt skills installer | [dbt-labs/dbt-agent-skills](https://github.com/dbt-labs/dbt-agent-skills) | `npx skills add dbt-labs/dbt-agent-skills` | Same as Skills CLI | M1 | `scripts/README.md` L8-L18 |
| LangChain skills | [langchain-ai/langchain-skills](https://github.com/langchain-ai/langchain-skills) | `npx skills add langchain-ai/langchain-skills --skill '*'` or `./install.sh` | `./install.sh` with no flag writes to `<project>/.claude` | M2 | `install.sh` L10, L97; `README.md` L53-L54 |
| OpenSkills | [numman-ali/openskills](https://github.com/numman-ali/openskills) | see upstream README | `./.claude/skills` by default; `--universal` switches to `./.agent/skills` | M2 | `README.md` L37, L82 |
| Ruflo (formerly claude-flow) | [ruvnet/ruflo](https://github.com/ruvnet/ruflo) | `npx ruflo@latest init` | `.claude/`, `.claude-flow/`, `CLAUDE.md` | M2 | `README.md` L10, L46, L204 |
| OpenSpec | [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) | `openspec init --tools <list>` | Claude: `.claude/skills/openspec-*`, `.claude/commands/opsx/`; Codex: `.agents/skills/openspec-*`; `--tools all` writes for every tool | M2 | `docs/supported-tools.md` L71, L76, L157 |
| Spec Kit | [github/spec-kit](https://github.com/github/spec-kit) | `specify init <project> --integration <agent>` | `claude`: `.claude/skills/speckit-*`; `codex`: `.agents/skills/speckit-*` | M2 | `docs/integrations/claude.md` L22; `docs/integrations/codex.md` L22 |

### Skills

| Skill | Upstream | Install | Writes to | Mechanism | Source |
|---|---|---|---|---|---|
| `databricks-jobs` | [databricks/databricks-agent-skills](https://github.com/databricks/databricks-agent-skills) | `databricks aitools install` | Tells the agent to create `CLAUDE.md` and `AGENTS.md` after scaffolding a bundle | M3 | `skills/databricks-jobs/SKILL.md` L35 |
| `warehouse-init` | [astronomer/agents](https://github.com/astronomer/agents) | `npx skills add astronomer/agents --skill '*'` | Offers to write the reference table to `CLAUDE.md`; creates `.claude/CLAUDE.md` if none exists | M3 | `skills/warehouse-init/SKILL.md` L206-L239 |
| `eval-engineering` | [langchain-ai/langchain-skills](https://github.com/langchain-ai/langchain-skills) | `npx skills add langchain-ai/langchain-skills` | Creates a project skill; names `.agents/skills/` and `.claude/skills/` as usual locations | M3 | `config/skills/eval-engineering/SKILL.md` L126-L133 |
| `skill-creator` | [anthropics/skills](https://github.com/anthropics/skills) | `npx skills add anthropics/skills` | Its eval script creates `.claude/commands/` in the project root and calls the `claude` command | M3 | `skills/skill-creator/scripts/run_eval.py` L45-L55 |
| `superpowers` | [obra/superpowers](https://github.com/obra/superpowers) | see upstream README | Writes and commits `docs/superpowers/specs/` and `plans/`; also `.superpowers/` | M3 | `skills/brainstorming/SKILL.md` L29; `skills/writing-plans/SKILL.md` L18 |

### Frameworks

| Tool | Version | Writes to | Mechanism | Source |
|---|---|---|---|---|
| `create-next-app` | Next.js 16.3 | `AGENTS.md` and `CLAUDE.md`; opt out with `--no-agents-md` | M4 | [ai-agents guide, 16.3.8](https://unpkg.com/next@16.3.8/dist/docs/01-app/02-guides/ai-agents.md) L37, L55 |
| `next dev` | Next.js 16.3 | `AGENTS.md` and `CLAUDE.md` at the project root when a coding agent is detected | M4 | same file, L63, L77-L79 |

The current canary documentation for Next.js describes only `AGENTS.md`, so this depends on the installed version.

## Keeping an install scoped to one agent

- Skills CLI: pass `-a <agent>` (for example `-a codex`) and `-g` for a global install instead of the project.
- Databricks CLI: pass `--agents <list>` and `--scope global`. Run `databricks aitools install --help` for the agent names.
- AI Dev Kit: pass `--tools <list>`.
- Firecrawl CLI: pass `--agent <name>`.
- Next.js: pass `--no-agents-md`, or set `agentRules: false`.

## Audit a project

`tools/collect-agent-evidence.sh` is a read-only script that reports which tool created the agent files in a project. It collects creation times, installer state files, git history, and the agent session records for that project, then writes a single report folder.

```bash
bash tools/collect-agent-evidence.sh /path/to/project
```

On Windows, use the PowerShell version:

```powershell
powershell -ExecutionPolicy Bypass -File tools\collect-agent-evidence.ps1 -ProjectPath C:\path\to\project
```

It never modifies the project, the agents' home folders or git. Session logs and shell history are not copied; only matching lines are written, truncated, with credential-looking lines dropped. The report still contains local paths, so review it before sharing and do not commit it (the `.gitignore` here excludes `agent-evidence-*/`).

Requirements for the bash version: bash, standard Unix tools, optionally `python3` and `zstd` (needed to read compressed Codex sessions). Tested on macOS.

Requirements for the PowerShell version: Windows PowerShell 5.1 or PowerShell 7, optionally `git` and `zstd` on PATH. It mirrors the bash version section by section but has not been run on Windows yet; if a section fails, the others still run and the error is printed to the console.

## Verify an entry yourself

```bash
curl -sL https://raw.githubusercontent.com/vercel-labs/skills/main/docs/agents.md | sed -n '17,19p;88p'
```

```bash
curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh | sed -n '1113,1160p'
```

```bash
curl -sL https://raw.githubusercontent.com/langchain-ai/langchain-skills/main/install.sh | sed -n '10p;97p'
```

## Researched but not confirmed

- Databricks MCP server: the AI Dev Kit marks it as deprecated with a separate installer, which was not read.
- Task Master and BMAD: the documentation read did not show where they write for Claude.
- Playwright `init-agents --loop=claude` and Context7 `ctx7 setup --claude`: the options exist; the paths written were not confirmed.

## What this catalog does and does not show

It shows, from upstream sources, that these tools can create Claude files without Claude Code being the agent in use. It does not show what happened on any particular machine; use the audit script for that.

A Portuguese write-up of the same findings is in [docs/findings-pt.md](docs/findings-pt.md).
