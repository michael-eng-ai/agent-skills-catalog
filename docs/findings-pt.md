# Dossie publico: skills e ferramentas que criam ambiente do Claude mesmo com outro agente

Data da pesquisa: 2026-11-18. Todas as afirmacoes abaixo vem de fonte primaria publica (README, documentacao oficial ou codigo-fonte do proprio projeto), lida nessa data. Cada item traz o arquivo e a linha para conferencia.

## 1. O que este documento demonstra

**Demonstra:** que existem ferramentas e skills publicas, de fornecedores conhecidos, que criam a pasta `.claude/`, o arquivo `CLAUDE.md` ou configuracao do Claude Code em um projeto ou na maquina, sem que o usuario esteja usando o Claude naquele momento. Isso ocorre por quatro mecanismos documentados (secao 2).

**Nao demonstra:** o que aconteceu em uma maquina ou repositorio especifico. Para isso e preciso evidencia local (secao 6). A pesquisa tambem nao encontrou relato publico (issue) de um caso identico; a demonstracao e pelo comportamento documentado das ferramentas, nao por precedente.

## 2. Os quatro mecanismos

| Mecanismo | Como funciona | Por que acontece usando Codex |
|---|---|---|
| M1. Instalador detecta todos os agentes | O instalador procura quais agentes existem na maquina e configura todos | Basta o Claude Code estar instalado, ou ter estado, para ele ser configurado junto |
| M2. Destino padrao e o Claude | Sem parametro, o instalador grava em `.claude/` | O usuario ou o agente roda o comando do README sem trocar o destino |
| M3. O texto da skill manda a IA criar arquivo do Claude | A instrucao esta escrita no `SKILL.md` ou em script da skill | Qualquer agente que leia a skill segue a instrucao, inclusive o Codex |
| M4. Framework gera o arquivo sozinho | O proprio framework cria `CLAUDE.md` ao rodar | Dispara ao detectar qualquer agente de codigo |

## 3. Lista por mecanismo

### M1. Instaladores que agem sobre todos os agentes detectados

| Ferramenta | Repositorio | O que a fonte diz | Onde conferir |
|---|---|---|---|
| Databricks CLI, `databricks aitools install` | github.com/databricks/databricks-agent-skills | Instala o plugin pelo CLI de cada agente (Claude Code, Codex, Copilot); em modo nao interativo age sobre todo agente detectado; escopo `project` ou `global` | `databricks aitools install --help`; docs.databricks.com/aws/en/dev-tools/cli/reference/aitools-commands |
| Databricks AI Dev Kit, `install.sh` | github.com/databricks-solutions/ai-dev-kit | A funcao `detect_tools` marca o Claude como ligado se o comando `claude` existir; instalacao basica e em escopo de projeto; a lista de pastas de projeto inclui `.claude` | `install.sh` linhas 1113-1160; `README.md` linhas 161 e 165 |
| Skills CLI, `npx skills add` | github.com/vercel-labs/skills | Detecta os agentes instalados; `--all` instala em todos os agentes sem perguntar; o destino do Claude Code e `.claude/skills/` e o do Codex e `.agents/skills/`; o padrao e escopo de projeto | `docs/agents.md` linhas 17, 19 e 88; `docs/commands.md` linhas 78 e 131 |
| Firecrawl CLI, `firecrawl init` | github.com/firecrawl/cli | Por padrao as skills sao roteadas para todo agente detectado; na selecao interativa todos vem marcados | `README.md` linhas 14-60 |
| dbt, `dbt-skills-install` | github.com/dbt-labs/dbt-agent-skills | Usa o Skills CLI por baixo; a opcao global e descrita como `~/.claude/skills/` | `scripts/README.md` linhas 8-18 |

O Skills CLI e o instalador recomendado por varios fornecedores de dados (LangChain, Astronomer, dbt Labs), entao o comportamento dele vale para todas essas skills.

### M2. Instaladores cujo destino padrao e o Claude

| Ferramenta | Repositorio | O que a fonte diz | Onde conferir |
|---|---|---|---|
| LangChain skills, `install.sh` | github.com/langchain-ai/langchain-skills | Variavel `TARGET` nasce como `claude`; sem parametro grava em `<projeto>/.claude` | `install.sh` linhas 10 e 97; `README.md` linhas 53-54 |
| OpenSkills, `openskills install` | github.com/numman-ali/openskills | O padrao e `./.claude/skills` no projeto, mesmo sendo vendido como carregador universal para Codex e outros | `README.md` linhas 37 e 82 |
| Ruflo (antigo claude-flow), `npx ruflo init` | github.com/ruvnet/ruflo | Apresenta-se como harness para Claude Code e Codex; o `init` cria `.claude/`, `.claude-flow/` e `CLAUDE.md` no projeto | `README.md` linhas 10, 46 e 204 |
| OpenSpec, `openspec init` | github.com/Fission-AI/OpenSpec | Para o Claude grava em `.claude/skills/openspec-*` e `.claude/commands/opsx/`; `--tools all` instala para todos | `docs/supported-tools.md` linhas 71, 76 e 157 |
| Spec Kit, `specify init` | github.com/github/spec-kit | Com `--integration claude` grava em `.claude/skills/speckit-*`; com `codex` grava em `.agents/skills/` | `docs/integrations/claude.md` linha 22; `docs/integrations/codex.md` linha 22 |

OpenSpec e Spec Kit so gravam em `.claude` se o Claude for escolhido; entram na lista porque a escolha errada, ou `--tools all`, produz o resultado.

### M3. Skills cujo texto manda a IA criar arquivos do Claude

Aqui esta o ponto de "confundir a IA": a instrucao esta no conteudo da skill, entao o agente que a executa cria o arquivo do Claude, seja ele qual for.

| Skill | Repositorio e commit | O que a instrucao manda | Onde conferir |
|---|---|---|---|
| `databricks-jobs` | github.com/databricks/databricks-agent-skills (plugin 0.2.20) | Depois do scaffold do bundle, criar `CLAUDE.md` e `AGENTS.md` na pasta do projeto | `skills/databricks-jobs/SKILL.md` linha 35 |
| `warehouse-init` | github.com/astronomer/agents, commit `535a040ca9e2` | Oferecer ao usuario gravar a tabela de referencia no `CLAUDE.md`; se nao existir, criar `.claude/CLAUDE.md` | `skills/warehouse-init/SKILL.md` linhas 206-239 |
| `eval-engineering` | github.com/langchain-ai/langchain-skills, commit `f179d57` | Criar a skill de projeto; cita `.agents/skills/` e `.claude/skills/` como destinos comuns | `config/skills/eval-engineering/SKILL.md` linhas 126-133 |
| `skill-creator` | github.com/anthropics/skills, commit `e4bb5d9` | O script de avaliacao cria `.claude/commands/` na raiz do projeto e chama o comando `claude` | `skills/skill-creator/scripts/run_eval.py` linhas 45-55 |
| `superpowers` | github.com/obra/superpowers, commit `896224c4b187` | Grava e commita `docs/superpowers/specs/` e `plans/`; a referencia de plataforma descreve `./.claude/CLAUDE.md` e `~/.claude/skills/` | `skills/brainstorming/SKILL.md` linha 29; `skills/using-superpowers/references/claude-code-tools.md` linhas 29-50 |

As skills da Databricks sao distribuidas tambem para o Codex (cada skill traz um `agents/openai.yaml`), portanto a instrucao da linha 35 chega ao Codex sem alteracao.

### M4. Frameworks que geram o arquivo sozinhos

| Ferramenta | O que a fonte diz | Onde conferir |
|---|---|---|
| Next.js 16.3, `create-next-app` | Gera `AGENTS.md` e `CLAUDE.md` automaticamente; desliga com `--no-agents-md` | unpkg.com/next@16.3.8/dist/docs/01-app/02-guides/ai-agents.md linhas 37 e 55 |
| Next.js 16.3, `next dev` | Ao detectar um agente de codigo no ambiente, gera `AGENTS.md` e `CLAUDE.md` na raiz; o `CLAUDE.md` contem apenas `@AGENTS.md` | mesmo arquivo, linhas 63 e 77-79 |

Observacao: a documentacao da versao canary atual descreve apenas `AGENTS.md`. O comportamento com `CLAUDE.md` esta documentado para a 16.3.8; depende da versao instalada.

## 4. Itens pesquisados e nao confirmados

- **Servidor MCP da Databricks:** o `install.sh` do AI Dev Kit informa que o MCP esta obsoleto e tem instalador separado (`databricks-mcp-server/mcp_install.sh`), que nao foi lido. O `install.sh` principal trata `.mcp.json` do projeto como arquivo que ele gerencia (linhas 584 e 721).
- **Task Master e BMAD:** a documentacao lida nao trouxe o trecho sobre `.claude`; ficam fora da lista.
- **Playwright (`init-agents --loop=claude`) e Context7 (`ctx7 setup --claude`):** existem as opcoes para Claude, mas o caminho gravado nao foi confirmado na fonte.
- **Relato publico de caso identico:** nao encontrado.

## 5. Como reproduzir cada verificacao

Os arquivos foram lidos em `https://raw.githubusercontent.com/<repositorio>/<branch>/<caminho>`. Exemplos:

```bash
curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh | sed -n '1113,1160p'
```

```bash
curl -sL https://raw.githubusercontent.com/vercel-labs/skills/main/docs/agents.md | sed -n '17,19p;88p'
```

```bash
curl -sL https://raw.githubusercontent.com/langchain-ai/langchain-skills/main/install.sh | sed -n '10p;97p'
```

```bash
databricks aitools install --help
```

Os branches `main` mudam com o tempo. Para um dossie que precise resistir a contestacao, troque `main` pelo commit vigente na data da consulta.

## 6. O que e preciso para ligar isso a um caso concreto

Para afirmar que foi uma dessas ferramentas que criou os arquivos em um projeto especifico, colete na maquina onde ocorreu:

1. Data de criacao dos arquivos: `stat` em `.claude/`, `CLAUDE.md` e vizinhos (`.agents/`, `.databricks/`, `skills-lock.json`, `.ai-dev-kit/`).
2. Arquivos de estado que os instaladores deixam: `.databricks/aitools/skills/.state.json` (Databricks CLI), `.ai-dev-kit/skills.lock` (AI Dev Kit), `skills-lock.json` (Skills CLI). Eles registram ferramenta, versao, escopo e horario.
3. Conteudo da pasta `.claude`: `skills/` ou `settings.json` com `enabledPlugins` apontam para instalador; `settings.local.json` com regras de permissao aponta para uso direto do Claude Code.
4. Log da sessao do Codex no horario (`~/.codex/sessions/AAAA/MM/DD/`), para mostrar qual comando foi executado.
5. `git log --diff-filter=A -- .claude CLAUDE.md`, para saber quem versionou os arquivos e quando.

Sem os itens 1 a 4, o dossie mostra que o cenario e possivel, nao que foi o que ocorreu.
