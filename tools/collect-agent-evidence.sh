#!/usr/bin/env bash
# collect-agent-evidence.sh
#
# Read-only evidence collector: explains which tool created Claude-related
# files (.claude/, CLAUDE.md) inside a project. It never modifies the project,
# the agents' home directories or git. The only thing it writes is one report
# folder (default: ./agent-evidence-<timestamp>/).
#
# Why: installers such as `databricks aitools install`, `npx skills add` or the
# AI Dev Kit configure every coding agent they detect, so Claude files can
# appear in a project where only another agent was being used. Proving which
# one did it requires timestamps, installer state files and session logs from
# the machine where it happened.
#
# Usage:
#   bash collect-agent-evidence.sh /path/to/project [output_dir]
#
# Privacy: session logs and shell history are never copied. Only matching
# lines are written, truncated, and lines that look like credentials are
# dropped. Review report.txt before sharing it.

set -u

PROJECT_INPUT="${1:-}"
if [ -z "$PROJECT_INPUT" ] || [ ! -d "$PROJECT_INPUT" ]; then
  echo "usage: bash collect-agent-evidence.sh /path/to/project [output_dir]" >&2
  exit 2
fi

PROJECT="$(cd "$PROJECT_INPUT" && pwd -P)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${2:-$PWD/agent-evidence-$RUN_ID}"
mkdir -p "$OUT_DIR" || { echo "cannot create $OUT_DIR" >&2; exit 2; }
REPORT="$OUT_DIR/report.txt"
HASHES="$OUT_DIR/sha256.txt"
: > "$REPORT"
: > "$HASHES"

MAX_LINE=220
SECRET_PATTERN='token|secret|password|passwd|apikey|api_key|bearer|authorization|BEGIN [A-Z ]*PRIVATE'
INSTALL_PATTERN='aitools install|ai-dev-kit|skills add|skills experimental_install|openskills (install|sync)|ruflo[^ ]* init|claude-flow[^ ]* init|create-next-app|next dev|specify init|openspec init|firecrawl[^ ]* (init|setup)|dbt-skills-install|langchain-skills|claude plugin (install|marketplace)|plugin install'
WRITE_PATTERN='(Add|Update) File: [^"]*(\.claude/|CLAUDE(\.local)?\.md)|mkdir[^"]{0,80}\.claude|(>|tee) +[^"]{0,100}(\.claude/|CLAUDE(\.local)?\.md)'

section() { printf '\n==================== %s ====================\n' "$1" >> "$REPORT"; }
note()    { printf '%s\n' "$*" >> "$REPORT"; }
redact()  { LC_ALL=C grep -aviE "$SECRET_PATTERN" | cut -c1-"$MAX_LINE"; }

# Creation and modification time, portable between BSD (macOS) and GNU stat.
file_times() {
  if stat -f '%SB' -t '%Y' "$1" >/dev/null 2>&1; then
    stat -f 'created=%SB modified=%Sm' -t '%Y-%m-%d %H:%M:%S' "$1" 2>/dev/null
  else
    stat -c 'created=%w modified=%y' "$1" 2>/dev/null | sed -E 's/\.[0-9]+ [+-][0-9]+//g'
  fi
}

file_hash() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null
  fi
}

# Prints a session log to stdout whether it is plain or zstd-compressed.
read_session() {
  case "$1" in
    *.zst) command -v zstd >/dev/null 2>&1 && zstd -dc "$1" 2>/dev/null ;;
    *)     cat "$1" 2>/dev/null ;;
  esac
}

# ---------------------------------------------------------------- 1. context
section "1. COLLECTION CONTEXT"
note "collected_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note "local_timezone:   $(date +%Z) (UTC$(date +%z))"
note "os:               $(uname -srm)"
note "project:          $PROJECT"
note "script_sha256:    $(file_hash "$0" | cut -d' ' -f1)"

# ------------------------------------------------- 2. agents the installers see
section "2. CODING AGENTS DETECTABLE ON THIS MACHINE"
note "Installers decide what to configure from these checks (command on PATH, app bundle, home folder)."
for tool in claude codex cursor gemini opencode kiro windsurf antigravity code databricks npx node uv; do
  tool_path="$(command -v "$tool" 2>/dev/null || true)"
  if [ -n "$tool_path" ]; then
    tool_version="$("$tool" --version 2>/dev/null | head -1 | cut -c1-80)"
    note "$(printf '%-12s on PATH: %s  version: %s' "$tool" "$tool_path" "${tool_version:-unknown}")"
  else
    note "$(printf '%-12s not on PATH' "$tool")"
  fi
done
for app in "Claude" "Codex" "ChatGPT" "Cursor" "Antigravity" "Visual Studio Code" "Windsurf" "Kiro"; do
  [ -d "/Applications/$app.app" ] && note "app bundle:  /Applications/$app.app ($(file_times "/Applications/$app.app"))"
done
for home_dir in .claude .codex .agents .cursor .gemini .antigravity .databricks .ai-dev-kit .config/opencode; do
  [ -e "$HOME/$home_dir" ] && note "home folder: ~/$home_dir ($(file_times "$HOME/$home_dir"))"
done

# ------------------------------------------------------ 3. project artifacts
section "3. AGENT ARTIFACTS INSIDE THE PROJECT (name, created, modified)"
find "$PROJECT" -maxdepth 5 \
  \( -name node_modules -o -name .git -o -name .venv -o -name venv -o -name worktrees \) -prune -o \
  \( -name .claude -o -name CLAUDE.md -o -name CLAUDE.local.md -o -name AGENTS.md -o -name GEMINI.md \
     -o -name .agents -o -name .codex -o -name .cursor -o -name .gemini -o -name .opencode -o -name .kiro \
     -o -name .ai-dev-kit -o -name skills-lock.json -o -name skills.lock -o -name .mcp.json \
     -o -name .superpowers -o -name .firecrawl -o -name .claude-flow -o -name .specify -o -name openspec \
     -o -name .brain -o -path '*/.databricks/aitools' -o -path '*/docs/superpowers' -o -path '*/.github/skills' \) \
  -print 2>/dev/null | sort | while IFS= read -r artifact; do
    note "$(printf '%-58s %s' "${artifact#"$PROJECT"/}" "$(file_times "$artifact")")"
  done

section "3b. FULL LISTING OF .claude FOLDERS (2 levels)"
find "$PROJECT" -maxdepth 5 -name .claude -type d -not -path '*/node_modules/*' -not -path '*/worktrees/*' 2>/dev/null | while IFS= read -r claude_dir; do
  note "--- ${claude_dir#"$PROJECT"/}"
  find "$claude_dir" -mindepth 1 -maxdepth 2 -not -path '*/worktrees/*/*' 2>/dev/null | sort | head -80 | while IFS= read -r entry; do
    kind="file"; [ -d "$entry" ] && kind="dir"; [ -L "$entry" ] && kind="link -> $(readlink "$entry")"
    note "$(printf '  %-52s %-6s %s' "${entry#"$claude_dir"/}" "$kind" "$(file_times "$entry")")"
  done
done

section "3c. CLAUDE SETTINGS FILES (structure only, values not dumped)"
note "settings.json with enabledPlugins points to an installer. settings.local.json with permission rules is written by Claude Code itself when the user approves a command."
find "$PROJECT" -maxdepth 6 -path '*/.claude/settings*.json' -not -path '*/worktrees/*' 2>/dev/null | while IFS= read -r settings_file; do
  note "--- ${settings_file#"$PROJECT"/} ($(file_times "$settings_file"))"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$settings_file" >> "$REPORT" 2>&1 <<'PYEOF'
import json
import sys

settings_path = sys.argv[1]
try:
    with open(settings_path, encoding="utf-8") as settings_handle:
        settings = json.load(settings_handle)
except (OSError, ValueError) as read_error:
    print(f"  unreadable: {read_error}")
    raise SystemExit(0)
print(f"  top_level_keys: {sorted(settings.keys())}")
print(f"  enabledPlugins: {settings.get('enabledPlugins', {})}")
permissions = settings.get("permissions", {})
for rule_kind in ("allow", "deny", "ask"):
    print(f"  permissions.{rule_kind}: {len(permissions.get(rule_kind, []))} rules")
print(f"  hooks_events: {sorted(settings.get('hooks', {}).keys())}")
PYEOF
  else
    note "  python3 not available; keys: $(LC_ALL=C grep -aoE '"(enabledPlugins|permissions|hooks|allow|deny)"' "$settings_file" | sort | uniq -c | tr '\n' ' ')"
  fi
  file_hash "$settings_file" >> "$HASHES"
done

section "3d. SYMLINKS UNDER AGENT FOLDERS (show which shared store feeds each agent)"
find "$PROJECT" -maxdepth 6 -type l \( -path '*/.claude/*' -o -path '*/.agents/*' -o -path '*/.gemini/*' -o -path '*/.cursor/*' -o -path '*/.codex/*' \) 2>/dev/null | sort > "$OUT_DIR/.symlinks.tmp"
note "total symlinks: $(wc -l < "$OUT_DIR/.symlinks.tmp" | tr -d ' ') (first 12 shown)"
head -12 "$OUT_DIR/.symlinks.tmp" | while IFS= read -r link_path; do
  note "${link_path#"$PROJECT"/} -> $(readlink "$link_path")"
done
rm -f "$OUT_DIR/.symlinks.tmp"

# ------------------------------------------------- 4. installer state files
section "4. INSTALLER STATE FILES (written by the installers themselves)"
find "$PROJECT" -maxdepth 6 \( -path '*/.databricks/aitools/*/.state.json' -o -path '*/.ai-dev-kit/skills.lock' -o -name skills-lock.json -o -path '*/.ai-dev-kit/*.json' \) -not -path '*/node_modules/*' 2>/dev/null | while IFS= read -r state_file; do
  note "--- ${state_file#"$PROJECT"/} ($(file_times "$state_file"))"
  LC_ALL=C grep -aE '"(schema_version|release|last_updated|scope|marketplace|plugin|version|source|sourceType|installedAt|agents?)"' "$state_file" | redact | head -30 >> "$REPORT"
  file_hash "$state_file" >> "$HASHES"
done
note ""
note "Home-level state:"
for home_state in "$HOME/.databricks/aitools/skills/.state.json" "$HOME/.agents/.skill-lock.json" "$HOME/.ai-dev-kit/skills.lock"; do
  [ -f "$home_state" ] && note "  present: $home_state ($(file_times "$home_state"))"
done

section "4b. .mcp.json FILES (server names only)"
find "$PROJECT" -maxdepth 4 -name .mcp.json -not -path '*/node_modules/*' 2>/dev/null | while IFS= read -r mcp_file; do
  note "--- ${mcp_file#"$PROJECT"/} ($(file_times "$mcp_file"))"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$mcp_file" >> "$REPORT" 2>&1 <<'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as mcp_handle:
        mcp_config = json.load(mcp_handle)
except (OSError, ValueError) as read_error:
    print(f"  unreadable: {read_error}")
    raise SystemExit(0)
for server_name, server_config in (mcp_config.get("mcpServers") or {}).items():
    launcher = server_config.get("command") or server_config.get("url") or "unknown"
    print(f"  server: {server_name} | launcher: {str(launcher)[:80]} | env_keys: {sorted((server_config.get('env') or {}).keys())}")
PYEOF
  fi
done

# ------------------------------------------------------------------- 5. git
section "5. GIT HISTORY OF THE AGENT FILES"
find "$PROJECT" -maxdepth 3 -name .git -not -path '*/node_modules/*' 2>/dev/null | while IFS= read -r git_marker; do
  repo_dir="$(dirname "$git_marker")"
  note "--- repository: ${repo_dir#"$PROJECT"} (root=$repo_dir)"
  note "tracked agent files: $(git -C "$repo_dir" ls-files -- .claude CLAUDE.md CLAUDE.local.md AGENTS.md .agents .mcp.json skills-lock.json docs/superpowers 2>/dev/null | wc -l | tr -d ' ')"
  note "commits that ADDED them (hash, date, author, subject):"
  git -C "$repo_dir" log --all --diff-filter=A --date=iso-strict --format='  %h %ad %an | %s' -- .claude CLAUDE.md AGENTS.md .agents .mcp.json skills-lock.json docs/superpowers 2>/dev/null | cut -c1-"$MAX_LINE" | tail -15 >> "$REPORT"
  note "ignored paths:"
  git -C "$repo_dir" check-ignore -v .claude CLAUDE.md CLAUDE.local.md .agents .mcp.json 2>/dev/null | sed 's/^/  /' >> "$REPORT"
  note "untracked or ignored on disk:"
  git -C "$repo_dir" status --porcelain --ignored -- .claude CLAUDE.md CLAUDE.local.md AGENTS.md .agents .mcp.json 2>/dev/null | sed 's/^/  /' | head -15 >> "$REPORT"
  note "commits carrying a Claude trailer, per author:"
  git -C "$repo_dir" log --all -i --grep='Co-Authored-By: Claude' --format='%an' 2>/dev/null | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /' >> "$REPORT"
done

# ------------------------------------------------ 6. Claude Code own records
section "6. CLAUDE CODE RECORDS FOR THIS PROJECT"
note "These show direct use of Claude Code in the project, independent of any installer."
PROJECT_SLUG="$(printf '%s' "$PROJECT" | sed 's/[^A-Za-z0-9]/-/g')"
if [ -d "$HOME/.claude/projects" ]; then
  for transcript_dir in "$HOME/.claude/projects/$PROJECT_SLUG"*; do
    [ -d "$transcript_dir" ] || continue
    transcript_count="$(find "$transcript_dir" -maxdepth 1 -name '*.jsonl' | wc -l | tr -d ' ')"
    note "$(basename "$transcript_dir"): $transcript_count transcripts (up to 15 listed)"
    find "$transcript_dir" -maxdepth 1 -name '*.jsonl' 2>/dev/null | while IFS= read -r transcript_file; do
      printf '  %s\n' "$(file_times "$transcript_file")"
    done | sort | head -15 >> "$REPORT"
  done
else
  note "~/.claude/projects does not exist"
fi
if [ -f "$HOME/.claude/plugins/installed_plugins.json" ]; then
  note ""
  note "installed_plugins.json entries (plugin, scope, projectPath, installedAt):"
  LC_ALL=C grep -aE '"[^"]+@[^"]+": *\[|"(scope|projectPath|installedAt|version)"' "$HOME/.claude/plugins/installed_plugins.json" | redact | sed 's/^ */  /' >> "$REPORT"
  file_hash "$HOME/.claude/plugins/installed_plugins.json" >> "$HASHES"
fi

# ------------------------------------------------------- 7. Codex sessions
section "7. CODEX SESSIONS IN THIS PROJECT"
codex_total=0
codex_in_project=0
if [ -d "$HOME/.codex" ]; then
  command -v zstd >/dev/null 2>&1 || note "WARNING: zstd not installed; compressed sessions (.jsonl.zst) cannot be read."
  find "$HOME/.codex/sessions" "$HOME/.codex/archived_sessions" -type f \( -name '*.jsonl' -o -name '*.jsonl.zst' \) 2>/dev/null | sort > "$OUT_DIR/.codex-sessions.tmp"
  while IFS= read -r session_file; do
    codex_total=$((codex_total + 1))
    session_cwd="$(read_session "$session_file" | head -c 200000 | LC_ALL=C grep -aoE '"cwd" *: *"[^"]+"' | head -1 | sed -E 's/.*: *"([^"]+)"/\1/')"
    case "$session_cwd" in
      "$PROJECT"|"$PROJECT"/*) ;;
      *) continue ;;
    esac
    codex_in_project=$((codex_in_project + 1))
    note "--- $(basename "$session_file") | cwd=$session_cwd"
    note "  install commands mentioned (review each: it may be documentation text, not an execution):"
    read_session "$session_file" | LC_ALL=C grep -aoE "\"timestamp\" *: *\"[^\"]{19}|($INSTALL_PATTERN)[^\"\\\\]{0,90}" | LC_ALL=C grep -aE -B1 "$INSTALL_PATTERN" | LC_ALL=C grep -av '^--$' | paste - - 2>/dev/null | redact | sort -u | head -12 | sed 's/^/    /' >> "$REPORT"
    note "  writes to Claude paths seen:"
    read_session "$session_file" | LC_ALL=C grep -aoE "$WRITE_PATTERN" | redact | sort | uniq -c | head -12 | sed 's/^/    /' >> "$REPORT"
    file_hash "$session_file" >> "$HASHES"
  done < "$OUT_DIR/.codex-sessions.tmp"
  rm -f "$OUT_DIR/.codex-sessions.tmp"
  note ""
  note "codex sessions on this machine: $codex_total | with cwd inside the project: $codex_in_project"
else
  note "~/.codex does not exist"
fi

# ------------------------------------------------------- 8. shell history
section "8. SHELL HISTORY: INSTALL COMMANDS"
note "History without timestamps cannot date a command; it only shows the command was typed on this machine."
for history_file in "$HOME/.zsh_history" "$HOME/.bash_history" "$HOME/.local/share/fish/fish_history"; do
  [ -f "$history_file" ] || continue
  note "--- $history_file (timestamped entries: $(LC_ALL=C grep -acE '^: [0-9]{9,}:' "$history_file"))"
  LC_ALL=C grep -anE "$INSTALL_PATTERN" "$history_file" | redact | tail -25 | sed 's/^/  /' >> "$REPORT"
done

# ----------------------------------------------------------- 9. reading aid
section "9. HOW TO READ THIS REPORT"
cat >> "$REPORT" <<'EOF'
Supports "an installer created the Claude files":
  - section 4 has a state file whose timestamp matches the .claude artifact in section 3;
  - section 3c shows settings.json with enabledPlugins, or section 3b shows skills/ or commands/;
  - section 7 shows a Codex session running an install command at that time.
Supports "Claude Code was used directly in the project":
  - section 3c shows settings.local.json with permission rules;
  - section 6 lists Claude Code transcripts for the project;
  - section 5 lists commits with a Claude trailer by the same author.
Both can be true for the same project. Report what each section shows.
EOF

note ""
note "sha256 of the evidence files is in: $HASHES"
echo "report written to: $REPORT"
echo "hashes written to: $HASHES"
