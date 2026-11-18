<#
.SYNOPSIS
    Read-only evidence collector: explains which tool created Claude-related
    files (.claude\, CLAUDE.md) inside a project.

.DESCRIPTION
    Installers such as `databricks aitools install`, `npx skills add` or the
    AI Dev Kit configure every coding agent they detect, so Claude files can
    appear in a project where only another agent was being used. Proving which
    one did it requires timestamps, installer state files and session logs
    from the machine where it happened.

    This script never modifies the project, the agents' home folders or git.
    The only thing it writes is one report folder.

    Privacy: session logs and shell history are never copied. Only matching
    excerpts are written, truncated, and excerpts that look like credentials
    are dropped. Review report.txt before sharing it.

.PARAMETER ProjectPath
    Folder of the project to inspect.

.PARAMETER OutputDir
    Where to write the report. Default: .\agent-evidence-<utc timestamp>\

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\collect-agent-evidence.ps1 -ProjectPath C:\work\my-project

.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ProjectPath,

    [Parameter(Position = 1)]
    [string]$OutputDir
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    Write-Error "project folder not found: $ProjectPath"
    exit 2
}

$Project = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath.TrimEnd('\', '/')
$RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
if (-not $OutputDir) { $OutputDir = Join-Path (Get-Location).Path "agent-evidence-$RunId" }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$Report = Join-Path $OutputDir 'report.txt'
$Hashes = Join-Path $OutputDir 'sha256.txt'
Set-Content -LiteralPath $Report -Value '' -Encoding UTF8
Set-Content -LiteralPath $Hashes -Value '' -Encoding UTF8

$HomeDir = $env:USERPROFILE
if (-not $HomeDir) { $HomeDir = $HOME }
$MaxLine = 220
$SecretPattern = 'token|secret|password|passwd|apikey|api_key|bearer|authorization|BEGIN [A-Z ]*PRIVATE'
$InstallPattern = 'aitools install|ai-dev-kit|skills add|skills experimental_install|openskills (install|sync)|ruflo[^ ]* init|claude-flow[^ ]* init|create-next-app|next dev|specify init|openspec init|firecrawl[^ ]* (init|setup)|dbt-skills-install|langchain-skills|claude plugin (install|marketplace)|plugin install'
$WritePattern = '(Add|Update) File: [^"]*(\.claude[\\/]|CLAUDE(\.local)?\.md)|mkdir[^"]{0,80}\.claude|New-Item[^"]{0,80}\.claude|(>|tee|Out-File|Set-Content) +[^"]{0,100}(\.claude[\\/]|CLAUDE(\.local)?\.md)'
$PrunedFolders = @('node_modules', '.git', '.venv', 'venv', 'worktrees')
$ArtifactNames = @(
    '.claude', 'CLAUDE.md', 'CLAUDE.local.md', 'AGENTS.md', 'GEMINI.md', '.agents', '.codex', '.cursor',
    '.gemini', '.opencode', '.kiro', '.ai-dev-kit', 'skills-lock.json', 'skills.lock', '.mcp.json',
    '.superpowers', '.firecrawl', '.claude-flow', '.specify', 'openspec', '.brain'
)
$ArtifactPathSuffixes = @('.databricks\aitools', 'docs\superpowers', '.github\skills')

function Add-Section {
    param([string]$Title)
    Add-Content -LiteralPath $Report -Value "`r`n==================== $Title ====================" -Encoding UTF8
}

function Add-Note {
    param([string]$Text)
    Add-Content -LiteralPath $Report -Value $Text -Encoding UTF8
}

function Limit-Text {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -gt $MaxLine) { return $Text.Substring(0, $MaxLine) }
    return $Text
}

function Test-LooksSecret {
    param([string]$Text)
    return ($Text -match $SecretPattern)
}

function Get-FileTimes {
    param([string]$Path)
    $entry = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $entry) { return 'created=? modified=?' }
    return ('created={0} modified={1}' -f $entry.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'), $entry.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
}

function Add-FileHash {
    param([string]$Path)
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction SilentlyContinue
    if ($hash) { Add-Content -LiteralPath $Hashes -Value ('{0}  {1}' -f $hash.Hash.ToLower(), $Path) -Encoding UTF8 }
}

function Get-RelativePath {
    param([string]$Path)
    if ($Path.Length -gt $Project.Length -and $Path.StartsWith($Project, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($Project.Length).TrimStart('\', '/')
    }
    return $Path
}

# Walks the tree with pruning, because Get-ChildItem -Recurse would descend
# into node_modules and .git and take minutes on real projects.
function Find-ProjectEntries {
    param([string]$Root, [int]$MaxDepth)
    $found = New-Object System.Collections.Generic.List[object]
    $pending = New-Object System.Collections.Generic.Stack[object]
    $pending.Push(@($Root, 0))
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $currentPath = $current[0]
        $currentDepth = [int]$current[1]
        $children = Get-ChildItem -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            $found.Add($child)
            $isLink = [bool]($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
            if ($child.PSIsContainer -and -not $isLink -and ($currentDepth + 1) -lt $MaxDepth -and ($PrunedFolders -notcontains $child.Name)) {
                $pending.Push(@($child.FullName, ($currentDepth + 1)))
            }
        }
    }
    return $found
}

function Read-SessionLines {
    param([string]$Path)
    if ($Path.EndsWith('.zst')) {
        if (Get-Command zstd -ErrorAction SilentlyContinue) { return (& zstd -dc $Path 2>$null) }
        return @()
    }
    return [System.IO.File]::ReadLines($Path)
}

# Reads only the session header, so sessions from other projects are skipped
# without loading the whole log.
function Get-SessionCwd {
    param([string]$Path)
    $headerLines = @()
    if ($Path.EndsWith('.zst')) {
        if (Get-Command zstd -ErrorAction SilentlyContinue) { $headerLines = @(& zstd -dc $Path 2>$null | Select-Object -First 50) }
    } else {
        $headerLines = @(Get-Content -LiteralPath $Path -TotalCount 50 -Encoding UTF8 -ErrorAction SilentlyContinue)
    }
    foreach ($headerLine in $headerLines) {
        if ($headerLine -match '"cwd"\s*:\s*"([^"]+)"') { return ($Matches[1] -replace '\\\\', '\') }
    }
    return $null
}

# ---------------------------------------------------------------- 1. context
Add-Section '1. COLLECTION CONTEXT'
Add-Note ('collected_at_utc: {0}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
Add-Note ('local_timezone:   {0} (UTC{1})' -f [System.TimeZoneInfo]::Local.Id, (Get-Date).ToString('zzz'))
Add-Note ('os:               {0}' -f [System.Environment]::OSVersion.VersionString)
Add-Note ('powershell:       {0}' -f $PSVersionTable.PSVersion.ToString())
Add-Note ('project:          {0}' -f $Project)
$scriptHash = Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256 -ErrorAction SilentlyContinue
if ($scriptHash) { Add-Note ('script_sha256:    {0}' -f $scriptHash.Hash.ToLower()) }

# ------------------------------------------------- 2. agents the installers see
Add-Section '2. CODING AGENTS DETECTABLE ON THIS MACHINE'
Add-Note 'Installers decide what to configure from these checks (command on PATH, install folder, home folder).'
foreach ($tool in @('claude', 'codex', 'cursor', 'gemini', 'opencode', 'kiro', 'windsurf', 'antigravity', 'code', 'databricks', 'npx', 'node', 'uv', 'git', 'zstd')) {
    $command = Get-Command $tool -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        Add-Note ('{0,-12} on PATH: {1}' -f $tool, $command.Source)
    } else {
        Add-Note ('{0,-12} not on PATH' -f $tool)
    }
}
$installFolders = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\cursor'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Windsurf'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Kiro'),
    (Join-Path $env:LOCALAPPDATA 'AnthropicClaude'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Claude')
)
foreach ($installFolder in $installFolders) {
    if (Test-Path -LiteralPath $installFolder) { Add-Note ('install folder: {0} ({1})' -f $installFolder, (Get-FileTimes $installFolder)) }
}
foreach ($homeFolder in @('.claude', '.codex', '.agents', '.cursor', '.gemini', '.antigravity', '.databricks', '.ai-dev-kit', '.config\opencode')) {
    $homePath = Join-Path $HomeDir $homeFolder
    if (Test-Path -LiteralPath $homePath) { Add-Note ('home folder:    ~\{0} ({1})' -f $homeFolder, (Get-FileTimes $homePath)) }
}

# ------------------------------------------------------ 3. project artifacts
$allEntries = Find-ProjectEntries -Root $Project -MaxDepth 6

Add-Section '3. AGENT ARTIFACTS INSIDE THE PROJECT (name, created, modified)'
$artifacts = $allEntries | Where-Object {
    $entryPath = $_.FullName
    ($ArtifactNames -contains $_.Name) -or (@($ArtifactPathSuffixes | Where-Object { $entryPath.EndsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0)
} | Sort-Object FullName
foreach ($artifact in $artifacts) {
    Add-Note ('{0,-58} {1}' -f (Get-RelativePath $artifact.FullName), (Get-FileTimes $artifact.FullName))
}

Add-Section '3b. FULL LISTING OF .claude FOLDERS (2 levels)'
$claudeFolders = $allEntries | Where-Object { $_.PSIsContainer -and $_.Name -eq '.claude' }
foreach ($claudeFolder in $claudeFolders) {
    Add-Note ('--- {0}' -f (Get-RelativePath $claudeFolder.FullName))
    $claudeEntries = Find-ProjectEntries -Root $claudeFolder.FullName -MaxDepth 2 | Sort-Object FullName | Select-Object -First 80
    foreach ($claudeEntry in $claudeEntries) {
        $kind = 'file'
        if ($claudeEntry.PSIsContainer) { $kind = 'dir' }
        if ($claudeEntry.LinkType) { $kind = 'link -> ' + (@($claudeEntry.Target) -join ',') }
        $relative = $claudeEntry.FullName.Substring($claudeFolder.FullName.Length).TrimStart('\', '/')
        Add-Note ('  {0,-52} {1,-6} {2}' -f $relative, $kind, (Get-FileTimes $claudeEntry.FullName))
    }
}

Add-Section '3c. CLAUDE SETTINGS FILES (structure only, values not dumped)'
Add-Note 'settings.json with enabledPlugins points to an installer. settings.local.json with permission rules is written by Claude Code itself when the user approves a command.'
$settingsFiles = $allEntries | Where-Object { -not $_.PSIsContainer -and $_.Name -like 'settings*.json' -and $_.Directory.Name -eq '.claude' }
foreach ($settingsFile in $settingsFiles) {
    Add-Note ('--- {0} ({1})' -f (Get-RelativePath $settingsFile.FullName), (Get-FileTimes $settingsFile.FullName))
    try {
        $settings = Get-Content -LiteralPath $settingsFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $topLevelKeys = @($settings.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object
        Add-Note ('  top_level_keys: {0}' -f ($topLevelKeys -join ', '))
        $enabledPlugins = @()
        if ($settings.enabledPlugins) { $enabledPlugins = @($settings.enabledPlugins.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) }
        Add-Note ('  enabledPlugins: {0}' -f ($enabledPlugins -join ', '))
        foreach ($ruleKind in @('allow', 'deny', 'ask')) {
            $ruleCount = 0
            if ($settings.permissions -and $settings.permissions.$ruleKind) { $ruleCount = @($settings.permissions.$ruleKind).Count }
            Add-Note ('  permissions.{0}: {1} rules' -f $ruleKind, $ruleCount)
        }
        $hookEvents = @()
        if ($settings.hooks) { $hookEvents = @($settings.hooks.PSObject.Properties | ForEach-Object { $_.Name }) }
        Add-Note ('  hooks_events: {0}' -f ($hookEvents -join ', '))
    } catch {
        Add-Note ('  unreadable: {0}' -f $_.Exception.Message)
    }
    Add-FileHash $settingsFile.FullName
}

Add-Section '3d. LINKS UNDER AGENT FOLDERS (show which shared store feeds each agent)'
$agentLinks = @($allEntries | Where-Object { $_.LinkType -and ($_.FullName -match '[\\/]\.(claude|agents|gemini|cursor|codex)[\\/]') } | Sort-Object FullName)
Add-Note ('total links: {0} (first 12 shown)' -f $agentLinks.Count)
foreach ($agentLink in ($agentLinks | Select-Object -First 12)) {
    Add-Note ('{0} -> {1}' -f (Get-RelativePath $agentLink.FullName), (@($agentLink.Target) -join ','))
}

# ------------------------------------------------- 4. installer state files
Add-Section '4. INSTALLER STATE FILES (written by the installers themselves)'
$stateFiles = $allEntries | Where-Object {
    -not $_.PSIsContainer -and (
        ($_.Name -eq '.state.json' -and $_.FullName -match '[\\/]\.databricks[\\/]aitools[\\/]') -or
        ($_.Name -eq 'skills-lock.json') -or
        ($_.FullName -match '[\\/]\.ai-dev-kit[\\/][^\\/]+\.(json|lock)$')
    )
}
foreach ($stateFile in $stateFiles) {
    Add-Note ('--- {0} ({1})' -f (Get-RelativePath $stateFile.FullName), (Get-FileTimes $stateFile.FullName))
    $stateLines = Select-String -LiteralPath $stateFile.FullName -Pattern '"(schema_version|release|last_updated|scope|marketplace|plugin|version|source|sourceType|installedAt|agents?)"' -ErrorAction SilentlyContinue | Select-Object -First 30
    foreach ($stateLine in $stateLines) {
        if (-not (Test-LooksSecret $stateLine.Line)) { Add-Note (Limit-Text $stateLine.Line) }
    }
    Add-FileHash $stateFile.FullName
}
Add-Note ''
Add-Note 'Home-level state:'
foreach ($homeState in @('.databricks\aitools\skills\.state.json', '.agents\.skill-lock.json', '.ai-dev-kit\skills.lock')) {
    $homeStatePath = Join-Path $HomeDir $homeState
    if (Test-Path -LiteralPath $homeStatePath) { Add-Note ('  present: {0} ({1})' -f $homeStatePath, (Get-FileTimes $homeStatePath)) }
}

Add-Section '4b. .mcp.json FILES (server names only)'
$mcpFiles = $allEntries | Where-Object { -not $_.PSIsContainer -and $_.Name -eq '.mcp.json' }
foreach ($mcpFile in $mcpFiles) {
    Add-Note ('--- {0} ({1})' -f (Get-RelativePath $mcpFile.FullName), (Get-FileTimes $mcpFile.FullName))
    try {
        $mcpConfig = Get-Content -LiteralPath $mcpFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($mcpConfig.mcpServers) {
            foreach ($server in $mcpConfig.mcpServers.PSObject.Properties) {
                $launcher = $server.Value.command
                if (-not $launcher) { $launcher = $server.Value.url }
                $envKeys = @()
                if ($server.Value.env) { $envKeys = @($server.Value.env.PSObject.Properties | ForEach-Object { $_.Name }) }
                Add-Note ('  server: {0} | launcher: {1} | env_keys: {2}' -f $server.Name, (Limit-Text ([string]$launcher)), ($envKeys -join ', '))
            }
        }
    } catch {
        Add-Note ('  unreadable: {0}' -f $_.Exception.Message)
    }
}

# ------------------------------------------------------------------- 5. git
Add-Section '5. GIT HISTORY OF THE AGENT FILES'
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitPaths = @('.claude', 'CLAUDE.md', 'AGENTS.md', '.agents', '.mcp.json', 'skills-lock.json', 'docs/superpowers')
    $repoFolders = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath (Join-Path $Project '.git')) { $repoFolders.Add($Project) }
    foreach ($candidate in (Find-ProjectEntries -Root $Project -MaxDepth 3 | Where-Object { $_.PSIsContainer })) {
        if ((Test-Path -LiteralPath (Join-Path $candidate.FullName '.git')) -and -not $repoFolders.Contains($candidate.FullName)) { $repoFolders.Add($candidate.FullName) }
    }
    foreach ($repoFolder in $repoFolders) {
        Add-Note ('--- repository: {0}' -f $repoFolder)
        $trackedFiles = @(& git -C $repoFolder ls-files -- @($gitPaths + 'CLAUDE.local.md') 2>$null)
        Add-Note ('tracked agent files: {0}' -f $trackedFiles.Count)
        Add-Note 'commits that ADDED them (hash, date, author, subject):'
        & git -C $repoFolder log --all --diff-filter=A --date=iso-strict '--format=  %h %ad %an | %s' -- $gitPaths 2>$null | Select-Object -Last 15 | ForEach-Object { Add-Note (Limit-Text $_) }
        Add-Note 'ignored paths:'
        & git -C $repoFolder check-ignore -v .claude CLAUDE.md CLAUDE.local.md .agents .mcp.json 2>$null | ForEach-Object { Add-Note ('  ' + $_) }
        Add-Note 'untracked or ignored on disk:'
        & git -C $repoFolder status --porcelain --ignored -- .claude CLAUDE.md CLAUDE.local.md AGENTS.md .agents .mcp.json 2>$null | Select-Object -First 15 | ForEach-Object { Add-Note ('  ' + $_) }
        Add-Note 'commits carrying a Claude trailer, per author:'
        & git -C $repoFolder log --all -i '--grep=Co-Authored-By: Claude' '--format=%an' 2>$null | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { Add-Note ('  {0,5} {1}' -f $_.Count, $_.Name) }
    }
} else {
    Add-Note 'git is not on PATH; section skipped.'
}

# ------------------------------------------------ 6. Claude Code own records
Add-Section '6. CLAUDE CODE RECORDS FOR THIS PROJECT'
Add-Note 'These show direct use of Claude Code in the project, independent of any installer.'
$claudeProjects = Join-Path $HomeDir '.claude\projects'
$projectSlug = $Project -replace '[^A-Za-z0-9]', '-'
if (Test-Path -LiteralPath $claudeProjects) {
    $transcriptFolders = Get-ChildItem -LiteralPath $claudeProjects -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name.StartsWith($projectSlug, [System.StringComparison]::OrdinalIgnoreCase) }
    if (-not $transcriptFolders) { Add-Note ('no transcript folder matching slug: {0}' -f $projectSlug) }
    foreach ($transcriptFolder in $transcriptFolders) {
        $transcripts = @(Get-ChildItem -LiteralPath $transcriptFolder.FullName -Filter '*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object CreationTime)
        Add-Note ('{0}: {1} transcripts (up to 15 listed)' -f $transcriptFolder.Name, $transcripts.Count)
        foreach ($transcript in ($transcripts | Select-Object -First 15)) { Add-Note ('  ' + (Get-FileTimes $transcript.FullName)) }
    }
} else {
    Add-Note '~\.claude\projects does not exist'
}
$installedPlugins = Join-Path $HomeDir '.claude\plugins\installed_plugins.json'
if (Test-Path -LiteralPath $installedPlugins) {
    Add-Note ''
    Add-Note 'installed_plugins.json entries (plugin, scope, projectPath, installedAt):'
    Select-String -LiteralPath $installedPlugins -Pattern '"[^"]+@[^"]+": *\[|"(scope|projectPath|installedAt|version)"' -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not (Test-LooksSecret $_.Line)) { Add-Note ('  ' + (Limit-Text $_.Line.Trim())) }
    }
    Add-FileHash $installedPlugins
}

# ------------------------------------------------------- 7. Codex sessions
Add-Section '7. CODEX SESSIONS IN THIS PROJECT'
$codexHome = Join-Path $HomeDir '.codex'
$codexTotal = 0
$codexInProject = 0
if (Test-Path -LiteralPath $codexHome) {
    if (-not (Get-Command zstd -ErrorAction SilentlyContinue)) { Add-Note 'WARNING: zstd not installed; compressed sessions (.jsonl.zst) cannot be read.' }
    $sessionFiles = @()
    foreach ($sessionRoot in @('sessions', 'archived_sessions')) {
        $sessionRootPath = Join-Path $codexHome $sessionRoot
        if (Test-Path -LiteralPath $sessionRootPath) {
            $sessionFiles += @(Get-ChildItem -LiteralPath $sessionRootPath -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.jsonl' -or $_.Name -like '*.jsonl.zst' })
        }
    }
    foreach ($sessionFile in ($sessionFiles | Sort-Object FullName)) {
        $codexTotal++
        $sessionCwd = Get-SessionCwd $sessionFile.FullName
        if (-not $sessionCwd) { continue }
        $inProject = ($sessionCwd -ieq $Project) -or $sessionCwd.StartsWith($Project + '\', [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $inProject) { continue }
        $installHits = New-Object System.Collections.Generic.List[string]
        $writeHits = @{}
        foreach ($sessionLine in (Read-SessionLines $sessionFile.FullName)) {
            $timestamp = '?'
            if ($sessionLine -match '"timestamp"\s*:\s*"([^"]{19})') { $timestamp = $Matches[1] }
            foreach ($installMatch in [regex]::Matches($sessionLine, "($InstallPattern)[^`"\\]{0,90}")) {
                $excerpt = '{0} {1}' -f $timestamp, $installMatch.Value
                if (-not (Test-LooksSecret $excerpt) -and -not $installHits.Contains($excerpt) -and $installHits.Count -lt 12) { $installHits.Add($excerpt) }
            }
            foreach ($writeMatch in [regex]::Matches($sessionLine, $WritePattern)) {
                $writeText = Limit-Text $writeMatch.Value
                if (-not (Test-LooksSecret $writeText)) { $writeHits[$writeText] = 1 + [int]$writeHits[$writeText] }
            }
        }
        $codexInProject++
        Add-Note ('--- {0} | cwd={1}' -f $sessionFile.Name, $sessionCwd)
        Add-Note '  install commands mentioned (review each: it may be documentation text, not an execution):'
        foreach ($installHit in $installHits) { Add-Note ('    ' + (Limit-Text $installHit)) }
        Add-Note '  writes to Claude paths seen:'
        foreach ($writeKey in ($writeHits.Keys | Select-Object -First 12)) { Add-Note ('    {0,4} {1}' -f $writeHits[$writeKey], $writeKey) }
        Add-FileHash $sessionFile.FullName
    }
    Add-Note ''
    Add-Note ('codex sessions on this machine: {0} | with cwd inside the project: {1}' -f $codexTotal, $codexInProject)
} else {
    Add-Note '~\.codex does not exist'
}

# ------------------------------------------------------- 8. shell history
Add-Section '8. SHELL HISTORY: INSTALL COMMANDS'
Add-Note 'PowerShell history has no timestamps; it only shows the command was typed on this machine.'
$historyFiles = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'),
    (Join-Path $HomeDir '.bash_history'),
    (Join-Path $HomeDir '.zsh_history')
)
foreach ($historyFile in $historyFiles) {
    if (-not (Test-Path -LiteralPath $historyFile)) { continue }
    Add-Note ('--- {0}' -f $historyFile)
    Select-String -LiteralPath $historyFile -Pattern $InstallPattern -ErrorAction SilentlyContinue | Select-Object -Last 25 | ForEach-Object {
        if (-not (Test-LooksSecret $_.Line)) { Add-Note ('  {0}: {1}' -f $_.LineNumber, (Limit-Text $_.Line)) }
    }
}

# ----------------------------------------------------------- 9. reading aid
Add-Section '9. HOW TO READ THIS REPORT'
Add-Note @'
Supports "an installer created the Claude files":
  - section 4 has a state file whose timestamp matches the .claude artifact in section 3;
  - section 3c shows settings.json with enabledPlugins, or section 3b shows skills\ or commands\;
  - section 7 shows a Codex session running an install command at that time.
Supports "Claude Code was used directly in the project":
  - section 3c shows settings.local.json with permission rules;
  - section 6 lists Claude Code transcripts for the project;
  - section 5 lists commits with a Claude trailer by the same author.
Both can be true for the same project. Report what each section shows.
'@
Add-Note ''
Add-Note ('sha256 of the evidence files is in: {0}' -f $Hashes)

Write-Output "report written to: $Report"
Write-Output "hashes written to: $Hashes"
