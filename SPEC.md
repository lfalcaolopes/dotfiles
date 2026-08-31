# Plano de implementação: dotfiles reproduzíveis para Omarchy

> Estado: plano consolidado; implementação ainda não iniciada; o fluxo
> `desktop` pode ser implementado e validado com um override no-op, mas sua
> segunda tela continuará incompleta até a captura indicada na seção 10.
> Diagnóstico de origem: 2026-08-29 e 2026-08-30.
> Ambiente de referência: Acer Nitro AN515-55, Omarchy `BUILD_ID 4.0.1`,
> kernel `7.1.9-arch1-2`, usuário `lfalcao`, shell `/usr/bin/zsh`.

## 1. Missão do agente

Construir neste repositório um bootstrap idempotente que, partindo de uma
instalação limpa do Omarchy 4, configure um dos dois hosts suportados:

- `notebook`: esta máquina, com painel interno, monitor Acer externo e kanata;
- `desktop`: o mesmo monitor Acer como principal, um segundo monitor e sem
  kanata.

O resultado deve reproduzir somente as preferências declaradas pelo usuário.
Defaults, arquivos gerados e estado de runtime do Omarchy não devem ser
copiados da máquina atual.

O bootstrap v1 está concluído quando:

1. `./bootstrap.sh notebook` e `./bootstrap.sh desktop` possuem fluxos válidos,
   ainda que o segundo monitor do desktop permaneça uma pendência de hardware;
2. uma segunda execução não causa erro nem duplica configuração;
3. Python, JavaScript/TypeScript e C#/.NET estão prontos para desenvolvimento;
4. configurações comuns, específicas do Omarchy e específicas de host estão
   isoladas;
5. segredos e estado local não entram no repositório;
6. tudo que exige interação humana está documentado em `docs/MANUAL.md`;
7. as verificações automatizáveis da seção 9 passam, e as verificações humanas
   ou dependentes de hardware ficam documentadas com seu resultado ou bloqueio.

## 2. Regras que não podem ser violadas

### 2.1 Escopo e ferramentas

- Usar Bash, GNU Stow e Git.
- Não introduzir chezmoi, Nix ou Ansible.
- Versionar apenas o delta em relação ao Omarchy 4.
- Preferir overrides mínimos a cópias completas de defaults do Omarchy.
- Não gerar listas a partir do estado bruto da máquina (`pacman -Qqe`,
  `code --list-extensions` etc.). As listas desta especificação já foram
  triadas.
- Todo módulo deve ser idempotente e executável isoladamente.
- O host é argumento obrigatório; não detectar por hostname ou hardware.

### 2.2 Responsabilidade sobre arquivos

- Não symlinkar arquivos que Omarchy, `gh`, `mise`, VS Code ou systemd alteram.
- `~/.config/git/config`, `~/.config/mise/config.toml` e
  `~/.config/Code/User/settings.json` devem ser configurados por comandos ou
  merge, nunca por Stow.
- A unit `kanata.service` deve ser copiada, não symlinkada. Uma unit linkada é
  removida por `systemctl --user disable` e deixa de poder ser habilitada.
- Configurações completas de terminal e idle não devem ser versionadas; aplicar
  somente os valores desejados sobre os arquivos criados pelo Omarchy.
- Usar `/usr/bin/grep` em scripts de verificação quando necessário, pois a
  máquina de origem possui uma função interativa chamada `grep`.

### 2.3 Segurança

Nunca versionar:

- `~/.ssh/`, `~/.gnupg/`, `~/.claude.json`;
- `~/.config/gh/hosts.yml`;
- credenciais do gcloud, Docker, 1Password ou Claude;
- diretórios de configuração de projetos pessoais que têm repositório próprio;
- arquivos `.ovpn`;
- históricos, caches, perfis de navegador ou storage do VS Code.

Antes de adicionar qualquer arquivo descoberto durante a implementação,
compará-lo com o default do Omarchy e confirmar sua origem:

```bash
diff /usr/share/omarchy/config/<path> "$HOME/.config/<path>"
cat /usr/share/omarchy/install/omarchy-{base,other}.packages \
  | /usr/bin/grep -vE '^\s*(#|$)'
/usr/bin/grep -m1 "installed <pkg> (" /var/log/pacman.log
```

## 3. Arquitetura alvo

```text
dotfiles/
├── SPEC.md
├── bootstrap.sh
├── lib/
│   └── common.sh
├── modules/
│   ├── 00-preflight.sh
│   ├── 05-locale.sh
│   ├── 10-packages.sh
│   ├── 15-browser.sh
│   ├── 17-terminal.sh
│   ├── 20-stow-common.sh
│   ├── 30-stow-omarchy.sh
│   ├── 35-stow-host.sh
│   ├── 40-shell.sh
│   ├── 45-kanata.sh
│   ├── 50-editors.sh
│   ├── 55-tweaks.sh
│   ├── 60-mise.sh
│   └── 70-manual.sh
├── config/
│   ├── systemd/
│   │   └── kanata.service
│   └── vscode/
│       └── settings.json
├── packages/
│   ├── core.txt
│   ├── host-notebook.txt
│   └── vscode-extensions.txt
├── stow/
│   ├── common/
│   ├── omarchy/
│   ├── host-notebook/
│   └── host-desktop/
└── docs/
    └── MANUAL.md
```

Existem três camadas:

| camada | função | aplicação |
|---|---|---|
| `common` | configuração portável para Linux | sempre |
| `omarchy` | overrides específicos do Omarchy | sempre |
| `host-<nome>` | monitor secundário e hardware do host | exatamente uma |

Não criar uma camada `optional`. O kanata pertence ao host `notebook`.

## 4. Contrato do bootstrap

### 4.1 Interface

```text
./bootstrap.sh <notebook|desktop> [--only <modulo>] [--dry-run]
```

Requisitos:

- sem host, sair com erro e listar hosts encontrados em `stow/host-*`;
- rejeitar host e módulo desconhecidos;
- `--only` aceita exclusivamente o basename de um arquivo em `modules/`, sem a
  extensão `.sh` (por exemplo, `10-packages`), e executa somente esse módulo;
- cada módulo valida por conta própria suas dependências de comandos, arquivos,
  argumentos e estado anterior, inclusive quando chamado por `--only`;
- `--dry-run` descreve mudanças sem realizá-las e não chama nenhum comando
  mutável. Isso inclui `sudo -v`, gerenciadores de pacotes, clones ou pulls,
  `chsh`, `systemctl`, instalação de extensões e `mise use`;
- em dry-run, validações que exigiriam um comando mutável devem apenas verificar
  pré-condições por meios somente leitura e informar o que seria executado. Modos
  somente leitura de uma ferramenta são permitidos e usados quando ela está
  presente: `stow -n` e `kanata --check`;
- dry-run não pode assumir a máquina já convergida. Uma ferramenta que outro
  módulo instalaria, ou um arquivo que ele criaria, é registrada como pendência
  com o módulo responsável, e a execução segue; fora do dry-run a mesma ausência
  é fatal;
- toda execução termina com um resumo agregado pelo bootstrap, em dry-run e na
  execução real: conflitos, consequências para a sessão e validações adiadas
  linha a linha, mais a contagem de mudanças. Silêncio significa máquina
  convergida. A contagem só inclui o que o módulo confirmou divergente por
  sondagem somente leitura, feita antes da escrita na execução real, nunca o
  número de comandos executados;
- depois do veredito, a execução lista os passos manuais que uma sondagem
  somente leitura não encontrou concluídos. Essa lista é independente da
  convergência: uma máquina convergida ainda pode ter login pendente. Um item
  sem sondagem possível, como o login do VS Code guardado no keyring, é marcado
  como tal no próprio texto e lembrado sempre;
- propagar falhas com mensagem que identifique o módulo;
- não assumir que o diretório atual é a raiz do repositório;
- reexecução deve convergir para o mesmo estado.

Trocar o host de uma máquina já configurada não é um fluxo suportado. Documentar
que isso exige `stow -D host-<antigo>` antes da nova execução.

### 4.2 Ordem dos módulos

1. `00-preflight.sh`: validar Omarchy/Arch, rede e, fora do dry-run, `sudo`;
   garantir Git e Stow. No dry-run, apenas relatar instalações necessárias.
2. `05-locale.sh`: convergir o teclado para `us` `pc105` `intl` e o console para
   `us-acentos`, via `localectl`.
3. `10-packages.sh`: instalar pacotes comuns e do host.
4. `15-browser.sh`: instalar o Brave e defini-lo como navegador padrão, pelos
   comandos do próprio Omarchy.
5. `17-terminal.sh`: instalar o ghostty e defini-lo como terminal padrão, pelos
   comandos do próprio Omarchy.
6. `20-stow-common.sh`: aplicar `stow/common`.
7. `30-stow-omarchy.sh`: aplicar `stow/omarchy`.
8. `35-stow-host.sh`: aplicar exatamente `stow/host-<host>`.
9. `40-shell.sh`: instalar oh-my-zsh/plugins, configurar shell, Git e perfil
   secundário do Claude.
10. `45-kanata.sh`: somente no notebook; copiar/habilitar a unit.
11. `50-editors.sh`: fazer merge do settings e instalar extensões do VS Code.
12. `55-tweaks.sh`: aplicar fontes de terminal e tempos de idle.
13. `60-mise.sh`: fixar as linhas de Node, pnpm e .NET.
14. `70-manual.sh`: sondar, sem escrever nada, os passos que o bootstrap não
    automatiza (logins, chave SSH, clone do vault, instaladores interativos) e
    registrar no resumo os que ainda faltam.

`lib/common.sh` deve concentrar pelo menos logging, detecção de comando,
criação de diretório e confirmação. Módulos não devem duplicar essa lógica.

### 4.3 Sequência para o usuário

Numa instalação nova, a ordem externa ao bootstrap é:

1. concluir a instalação limpa do Omarchy;
2. instalar Brave e defini-lo como navegador padrão;
3. clonar este repositório;
4. executar `./bootstrap.sh notebook` ou `./bootstrap.sh desktop`;
5. concluir os passos interativos de `docs/MANUAL.md`, que o `70-manual.sh`
   lista no fim de cada execução enquanto continuarem pendentes.

### 4.4 Estratégia de testes

Testes de bootstrap devem executar com um `HOME` temporário, fixtures mínimas
para representar os arquivos existentes e um `PATH` controlado com shims para
comandos externos. Os shims devem registrar chamadas e permitir simular
sucesso, ausência e falha sem usar a configuração ou os serviços da estação.
Nenhum teste automatizado pode depender do `$HOME` real.

São automatizáveis: parsing e rejeição de argumentos, descoberta de hosts,
seleção por `--only`, validação isolada das dependências de cada módulo,
ordenação, propagação de erros, contrato de dry-run, migração dos conflitos do
Stow, merges e idempotência de arquivos. O teste de dry-run deve falhar se o
log dos shims registrar qualquer comando mutável proibido na seção 4.1.

São verificações humanas ou dependentes de hardware: autenticações, teclas em
terminal/tmux/SSH, reload e erros do Hyprland, EDID/modo/posição e refresh rate
dos monitores, regras de janela e classe real do DBeaver, além do funcionamento
físico do kanata. Elas não bloqueiam testes automatizados quando o hardware ou
a sessão gráfica correspondente não está disponível; o resultado ou bloqueio
deve ser registrado no manual.

## 5. Plano de implementação

Cada fase abaixo deve terminar com seus critérios de aceite antes da próxima.

### Fase 0 — proteger o trabalho

- Inicializar este diretório como repositório Git válido. O `.git` existente
  está vazio e `git status` não reconhece o diretório como repositório.
- Criar um `.gitignore` conservador, sem padrões que escondam arquivos da
  estrutura alvo.
- Fazer um commit do plano antes de capturar configurações da máquina.

Critério de aceite: `git status` funciona e o `SPEC.md` possui histórico.

### Fase 1 — criar o esqueleto e a orquestração

- Criar a árvore da seção 3.
- Implementar parsing de argumentos e descoberta de hosts.
- Implementar `--only`, `--dry-run` e execução ordenada dos módulos.
- Definir utilitários comuns em `lib/common.sh`.
- Adicionar `set -Eeuo pipefail` aos scripts e mensagens de erro úteis.

Critérios de aceite:

- execução sem host falha antes de alterar a máquina;
- hosts inválidos falham antes de alterar a máquina;
- dry-run percorre o plano completo sem escrever;
- dry-run não invoca nenhum comando mutável, comprovado pelo log dos shims;
- dry-run conclui numa máquina sem stow, zsh, mise, kanata nem code, e aborta
  quando uma verificação somente leitura reprova;
- dry-run numa máquina convergida termina com `nada a fazer`, e reage quando um
  runtime sai do pino ou surge um conflito;
- a execução real numa máquina convergida também termina com `nada a fazer`,
  conta o que mudou quando há divergência e diz o que ficou para a pessoa fazer
  a mão;
- cada valor aceito por `--only` funciona em teste isolado, e nomes com `.sh`
  ou inexistentes são rejeitados antes de qualquer alteração;
- a suíte usa `HOME` temporário e não altera a estação de trabalho;
- ShellCheck não encontra erros relevantes, se estiver disponível.

### Fase 2 — pacotes

Criar `packages/core.txt` com:

```text
visual-studio-code-bin
postman-bin
dbeaver
steam
zsh
python-pipx
```

Criar `packages/host-notebook.txt` com:

```text
kanata-bin
```

Não criar `host-desktop.txt` vazio; o módulo deve aceitar sua ausência.

No módulo, separar pacotes oficiais de AUR. `postman-bin` e `kanata-bin` são
AUR; os demais estão em repositórios configurados pelo Omarchy. Usar:

```bash
sudo pacman -S --needed --noconfirm ...
yay -S --needed --noconfirm ...
```

Não adicionar os pacotes rejeitados da seção 8.2.

Critério de aceite: uma segunda execução não reinstala pacotes nem falha por
listas ausentes.

### Fase 3 — configuração comum

Popular `stow/common` com:

```text
.zshrc
.config/starship.toml
.config/Code/User/keybindings.json
.config/git/ignore
.local/bin/hypr-close-window
.claude/CLAUDE.md
.claude/settings.json
.claude/statusline-command.sh
.claude/commands/
```

Capturar o conteúdo da máquina de origem somente depois de aplicar as regras a
seguir.

#### Migração inicial para o Stow

A máquina de origem já possui arquivos regulares nos destinos que passarão a
ser gerenciados. Depois de capturar e revisar cada arquivo no pacote correto, o
módulo Stow deve tratar cada folha conflitante antes de criar links:

1. criar um diretório de backup exclusivo sob
   `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<timestamp>/`;
2. copiar o arquivo ou symlink conflitante com metadados e caminho relativo
   preservados, verificar que o backup existe e só então remover a folha do
   destino;
3. abortar sem sobrescrever backups ou remover diretórios que contenham itens
   não gerenciados;
4. executar `stow --restow` somente após todos os conflitos do pacote estarem
   protegidos e registrar o caminho do backup para o usuário.

Nunca usar `stow --adopt`: ele pode reescrever a cópia versionada com o estado
local. Links já corretos não são conflitos e a reexecução não deve criar novo
backup. Em `--dry-run`, apenas listar conflitos, destinos de backup e comandos
planejados, sem criar, copiar, remover ou chamar Stow. Testar esse fluxo com
fixtures em um `HOME` temporário, incluindo arquivo regular, symlink incorreto,
link já correto e diretório com conteúdo não gerenciado.

#### `.zshrc`

Manter oh-my-zsh e remover somente o plugin `git`.

Estrutura obrigatória:

| bloco | conteúdo |
|---|---|
| oh-my-zsh | `ZSH="$HOME/.oh-my-zsh"`, plugins `zsh-autosuggestions` e `zsh-syntax-highlighting`, depois `source $ZSH/oh-my-zsh.sh` |
| histórico | `HISTFILE=~/.zsh_history`, `HISTSIZE=32768`, `SAVEHIST=32768` |
| comportamento | `interactivecomments`; sem `correct` e sem `autocd` explícito |
| ferramentas | mise, starship, zoxide e fzf |
| ambiente | `MANROFFOPT`, `MANPAGER`, `BAT_THEME`, `EDITOR`, `SUDO_EDITOR`, `BROWSER` |
| PATH | prepend de `~/.local/bin` |
| aliases | `ls`, `ll`, `la`, `dev`, `notes`, `home`, `zshconfig`, `claude-dio`, `kanata-start`, `kanata-stop` |

Ordem obrigatória: carregar oh-my-zsh antes das ferramentas e carregar fzf por
último, para que ele controle `Ctrl-R`.

```sh
eval "$(mise activate zsh)"
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
source <(fzf --zsh)
```

Remover blocos de nvm, `.meteor` e `PNPM_HOME`. Remover aliases `vpn*`,
`ohmyzsh` e `claude-personal`.

`EDITOR` deve usar `omarchy-launch-editor --inline` quando disponível e `nvim`
como fallback. `SUDO_EDITOR` acompanha `EDITOR`. `BROWSER` deve ficar somente no
shell; não movê-lo para `.zshenv` nem `environment.d`, pois interfere no
`xdg-settings`.

Configurar man pages:

```sh
export MANROFFOPT="-c"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export BAT_THEME=ansi
```

#### `starship.toml`

- Manter o layout powerline do preset `gruvbox-rainbow`.
- Trocar cores hexadecimais por nomes ANSI numa paleta `[palettes.omarchy]`.
- Usar `color_on_accent = "black"` e `color_on_neutral = "white"`.
- Definir `command_timeout = 200`.
- Manter módulos `os`, `username`, `directory`, `git_branch`, `git_status`,
  `nodejs`, `python`, `dotnet`, `docker_context` e `time`.
- Remover `c`, `cpp`, `rust`, `golang`, `php`, `java`, `kotlin`, `haskell`,
  `conda` e `pixi`.
- Não adicionar `cmd_duration` nem prompt transiente.
- Ativar `[dotnet]`; ao final do bootstrap o SDK existe via mise.
- Em `[dotnet]`, manter `heuristic = true`.
- Preservar todos os estados do Git. Usar os símbolos definidos na seção 8.3.

Ao editar, não confiar em cópia visual dos glifos powerline. Preservá-los a
partir do arquivo original ou escrever por codepoint e validar os codepoints do
campo `format`.

#### Git

`~/.config/git/ignore` deve conter:

```gitignore
**/.claude/settings.local.json
```

Não versionar `~/.config/git/config`. Em `40-shell.sh`, aplicar:

```bash
git config --global user.name "Lucas Falcao Lopes"
git config --global user.email "lfalcaolopes@gmail.com"
```

Não configurar credential helper; `gh auth login` fará isso.

#### Claude Code

- Versionar somente os itens listados em `stow/common`.
- Manter no `settings.json` global somente preferências globais. Não incluir
  `autoMode.environment`, permissões ou `soft_deny` específicos de `~/notes`.
- As regras do vault, incluindo não executar commit ou push manualmente,
  pertencem ao `~/notes/CLAUDE.md` e não a este repositório.
- Tornar o caminho do `statusLine.command` portável, sem fixar
  `/home/lfalcao`.
- Em `40-shell.sh`, criar `~/.claude-dio`, apontar seu `CLAUDE.md` para o perfil
  principal e criar um `settings.json` mínimo com tema `dark` e modelo `opus`.
- Não criar links `agents` ou `rules` no perfil secundário.
- Nunca copiar `.credentials.json` de nenhum perfil.

#### `hypr-close-window`

- Remover `/home/lfalcao` de qualquer caminho.
- Se `~/notes` não existir ou não for um repositório Git, sair silenciosamente
  do trecho relacionado a notas.

Critérios de aceite:

- Stow não cria conflitos numa instalação limpa;
- nenhum arquivo versionado contém `/home/lfalcao`, token ou credencial;
- `zsh -i -c 'command -v node'` resolve pelo mise;
- Ctrl-R continua pertencendo ao fzf;
- o `starship.toml` é válido e preserva seus glifos.

### Fase 4 — overrides do Omarchy e hosts

Popular `stow/omarchy` apenas com overrides:

```text
.config/hypr/bindings.lua
.config/hypr/input.lua
.config/hypr/looknfeel.lua
.config/hypr/hyprland.lua
.config/hypr/monitors.lua
```

#### `bindings.lua`

- Manter as duas bindings de `hypr-close-window`.
- Definir `binds.workspace_back_and_forth = true`.
- Remover as duas bindings de `hyprvoice`; o voxtype nativo usa F9.
- Chamar `hypr-close-window` sem caminho absoluto de usuário.

#### `input.lua`

- compose no Alt direito;
- `repeat_delay = 600`;
- `natural_scroll` conforme o estado atual do usuário;
- `clickfinger_behavior = false`;
- `drag_3fg = 1`;
- gesto horizontal de quatro dedos para workspaces.

Não habilitar gestos de três dedos para foco: conflitam com `drag_3fg`. Deixar
um comentário curto no arquivo explicando o conflito.

#### `looknfeel.lua`

```lua
gaps_in = 2
gaps_out = 4
rounding = 8
resize_on_border = true
snap.enabled = true
```

#### `hyprland.lua`

- Carregar `require("hypr.host")` como ponto de extensão do host.
- Aplicar as regras abaixo:

```lua
o.window("^([bB]rave-browser)$", { workspace = "1 silent" })
o.window("^(code)$",             { workspace = "2 silent" })
o.window("^([dD][bB]eaver)$",    { workspace = "3 silent" })
o.window("^([Pp]ostman)$",       { workspace = "4 silent" })
o.window("^([sS]team)$",         { workspace = "5 silent" })
o.window("^brave-web\.whatsapp\.com__", { workspace = "6 silent" })

o.window("^([sS]team)$",   { tile = true })
o.window("^([Pp]ostman)$", { tile = true })
```

A classe do DBeaver foi inferida do `.desktop`, não validada ao vivo. Marcar
essa verificação no manual. Não adicionar regra automática de scratchpad.

#### `monitors.lua` comum

- Manter `GDK_SCALE` e o fallback genérico `output = ""`.
- Declarar primeiro o monitor principal, por descrição EDID:

```lua
hl.monitor({
  output = "desc:Acer Technologies QG241Y P",
  mode = "1920x1080@165",
  position = "auto",
  scale = 1,
})
```

- Fixar workspaces 1–5 nesse monitor usando a mesma descrição, não o conector.
- Não incluir o serial EDID; o match por prefixo foi validado.
- Deixar a segunda tela e workspaces 6–10 para `hypr.host`.

#### `host-notebook`

Fornecer:

```text
.config/hypr/host.lua
.config/kanata/<arquivos atuais>
```

`host.lua` deve configurar `eDP-1` como segunda tela e fixar workspaces 6–10
nele. Absorver os dois arquivos do repositório local `~/.config/kanata`, mas não
copiar seu `.git`.

#### `host-desktop`

Fornecer `.config/hypr/host.lua` com a mesma intenção: segundo monitor e
workspaces 6–10. O identificador EDID, modo e posição desse monitor ainda
precisam ser capturados no desktop. Até isso ocorrer, o arquivo deve ser Lua
válida, conter apenas comentários explícitos sobre a pendência e não executar
configuração alguma nem inventar um conector. Esse no-op torna o fluxo de
bootstrap do desktop válido, mas não conclui sua configuração física nem fixa
os workspaces 6–10.

Critérios de aceite:

- `luac`/parser do Omarchy aceita os arquivos;
- `hyprctl reload` não produz `configerrors` no notebook;
- o Acer opera a aproximadamente 165 Hz;
- Brave, Code, Postman, Steam e WhatsApp caem nos workspaces definidos;
- validar a classe real do DBeaver com `hyprctl clients`;
- uma máquina sem touchpad aceita `input.lua` sem erro.
- o `host.lua` provisório do desktop passa no parser como no-op; EDID, modo,
  posição e workspaces 6–10 só são aceitos após validação no hardware desktop.

### Fase 5 — shell, kanata e mise

#### Dependências do zsh

Em `40-shell.sh`, instalar ou atualizar de modo idempotente:

- `~/.oh-my-zsh` de `https://github.com/ohmyzsh/ohmyzsh`;
- `zsh-autosuggestions` em `$ZSH_CUSTOM/plugins/`;
- `zsh-syntax-highlighting` em `$ZSH_CUSTOM/plugins/`.

Não executar instaladores interativos. Clonar quando ausente e atualizar um
checkout limpo quando presente. Não sobrescrever repositórios com alterações
locais. Alterar o shell para zsh somente quando necessário.

#### kanata

Em `45-kanata.sh`, somente para `notebook`:

- confirmar que `kanata-bin` e os arquivos de configuração existem;
- copiar `config/systemd/kanata.service` para `~/.config/systemd/user/`;
- executar daemon-reload, enable e start/restart de maneira convergente.

O caminho `/dev/input/by-path/platform-i8042-serio-0-event-kbd` é válido porque
essa configuração só existe no host notebook.

#### mise e linguagens obrigatórias

Em `60-mise.sh`, executar sempre:

```bash
mise use -g node@24
mise use -g pnpm@12
mise use -g dotnet@10
```

Política fechada:

- Node 24 é a linha LTS escolhida;
- .NET 10 é a linha LTS escolhida e o backend fornece o SDK;
- pnpm fica na major 12;
- majors são deliberadamente fuzzy para receber patches sem migrar de linha;
- versões por projeto podem ser mais específicas em `mise.toml` local;
- não habilitar leitura global de `.nvmrc` neste v1.

Python vem do sistema. `venv` e `ensurepip` são suficientes para projetos;
`python-pipx` cobre CLIs. Não instalar `python-pip` global nem fixar outra versão
de Python: o Arch protege o ambiente global conforme a PEP 668. Projetos podem
pedir uma versão pelo mise no futuro. `npm` e `npx` vêm junto com o Node do mise.

Critérios de aceite:

```bash
zsh -i -c 'node --version'
zsh -i -c 'npm --version'
zsh -i -c 'pnpm --version'
zsh -i -c 'dotnet --version'
dotnet new --list
python -m venv /tmp/dotfiles-venv-check
```

Node deve estar na linha 24, pnpm na 12 e o comando .NET deve reportar SDK 10.

### Fase 6 — VS Code e tweaks mutáveis

#### Preferências do VS Code

Criar `config/vscode/settings.json` com as preferências do usuário, excluindo:

- `workbench.colorTheme`;
- todo o bloco `github.copilot.*`;
- `extensions.experimental.affinity` para `asvetliakov.vscode-neovim`;
- `workbench.colorCustomizations` com cores fixas do cursor.

Adicionar:

```json
"workbench.iconTheme": "material-icon-theme"
```

Em `50-editors.sh`, fazer merge do objeto sobre o settings local com `jq`,
preservando chaves que não estão na fonte gerenciada e gravando atomicamente.
Não seguir o symlink nem escrever no repositório acidentalmente.

#### Extensões

Criar `packages/vscode-extensions.txt` exatamente com:

```text
anthropic.claude-code
astro-build.astro-vscode
bradlc.vscode-tailwindcss
christian-kohler.path-intellisense
dbaeumer.vscode-eslint
docker.docker
drcika.apc-extension
dsznajder.es7-react-js-snippets
eamodio.gitlens
esbenp.prettier-vscode
formulahendry.auto-rename-tag
kreativ-software.csharpextensions
moalamri.inline-fold
ms-dotnettools.csdevkit
ms-dotnettools.csharp
ms-dotnettools.vscode-dotnet-runtime
ms-python.debugpy
ms-python.python
ms-python.vscode-pylance
ms-python.vscode-python-envs
naumovs.color-highlight
patcx.vscode-nuget-gallery
pkief.material-icon-theme
prisma.prisma
skattyadz.vscode-quick-scope
styled-components.vscode-styled-components
tomoki1207.pdf
usernamehw.errorlens
vscodevim.vim
zhuangtongfa.material-theme
```

Instalar com `code --install-extension`. Não incluir extensões de temas do
Omarchy; o próprio `omarchy-theme-set-vscode` as instala.

#### Tweaks

Em `55-tweaks.sh`, alterar somente:

- tamanho de fonte para 11 em Alacritty, Foot, Ghostty e Kitty;
- `idle.lock` para `3600` em `~/.config/omarchy/shell.json`;
- `idle.screensaver` para `86400` no mesmo arquivo.

Usar ferramenta adequada ao formato (`sed` ou `jq`), preservar o restante e
falhar com mensagem clara se o formato esperado tiver mudado. Não configurar
`shell.toml base-size` nem dconf.

Critérios de aceite:

- duas execuções produzem arquivos byte a byte iguais;
- trocar o tema do Omarchy não altera arquivos versionados;
- o merge mantém `workbench.colorTheme` local;
- todas as extensões declaradas aparecem em `code --list-extensions`.

### Fase 7 — documentação e teste final

Criar `docs/MANUAL.md` na ordem real de uso:

1. instalar Brave com `omarchy install browser brave` e defini-lo como padrão,
   caso isso não tenha sido feito antes do clone;
2. gerar uma nova chave SSH;
3. autenticar o GitHub por SSH (`gh auth login --git-protocol ssh`), que também
   registra a chave pública, mais Slack, Signal, Steam, Docker Hub e navegador;
4. importar chave GPG somente se ainda necessária;
5. instalar 1Password pelo menu do Omarchy;
6. instalar voxtype com `omarchy-voxtype-install` se ditado for desejado;
7. clonar o vault do Obsidian em `~/notes`, de que o alias `notes` e o
   autocommit do `hypr-close-window` dependem;
8. copiar VPNs por canal seguro e recriar comandos locais;
9. definir o tema built-in `hackerman`;
10. validar monitor, refresh rate e regras de janela;
11. no desktop, capturar EDID/modo/posição do segundo monitor e finalizar
    `stow/host-desktop/.config/hypr/host.lua`;
12. entrar no perfil secundário usando `claude-dio` e `/login`.

Documentar que o flag `silent` pode abrir aplicativos em workspaces não visíveis
quando o notebook estiver com apenas um monitor. Isso é comportamento esperado.

Executar o bootstrap completo em dry-run, depois no notebook, depois novamente
no notebook. Antes da aplicação real, executar a suíte isolada da seção 4.4.
Registrar no README ou manual qualquer pré-condição, verificação humana ou
bloqueio de hardware encontrado.

## 6. Matriz de ownership

| item | método | responsável depois do bootstrap |
|---|---|---|
| `.zshrc`, starship, keybindings, git ignore | Stow common | repositório |
| Hyprland overrides | Stow omarchy | repositório |
| `hypr.host`, kanata config | Stow host | repositório |
| `kanata.service` | cópia | systemd/módulo |
| Git identity | `git config` | Git |
| mise globals | `mise use -g` | mise |
| VS Code settings | merge atômico | VS Code + módulo |
| VS Code extensions | comandos `code` | VS Code |
| terminal font size e idle | edição dirigida | Omarchy + módulo |
| navegador e terminal padrão | comandos do Omarchy | módulo |
| tema, logins, voxtype, vault `~/notes` | manual | usuário/Omarchy |

Use esta tabela para decidir onde colocar qualquer configuração nova.

## 7. Decisões fechadas

Não reabrir estas decisões durante o v1 sem nova evidência ou pedido do usuário:

- oh-my-zsh fica; somente o plugin `git` sai;
- nvm sai e mise governa Node, pnpm e .NET;
- linguagens usam linhas LTS/major, não `latest`;
- voxtype é manual; hyprvoice não entra;
- Brave substitui Opera e usa o launcher nativo do Omarchy;
- configurações são divididas em `common`, `omarchy` e `host-*`;
- `settings.json` do VS Code é merge, não symlink;
- `git/config` e `mise/config.toml` não são versionados;
- projetos pessoais permanecem em seus próprios repositórios;
- agentes e memórias do Claude não entram;
- não há bloco dconf;
- `tweaks.sh` faz parte do v1;
- monitor principal é identificado por descrição EDID, não por conector;
- kanata é exclusivo do notebook;
- nenhuma regra automática de scratchpad entra no v1.

## 8. Referência técnica e exclusões

Esta seção explica decisões que o agente pode precisar consultar, mas não faz
parte da sequência de execução.

### 8.1 O que pertence ao Omarchy ou é estado gerado

Não capturar:

- `~/.config/nvim/`: skel de `omarchy-nvim`, e a cópia local está antiga;
- `~/.config/tmux/tmux.conf`: cópia antiga do default;
- `~/.config/btop/btop.conf`: diferença produzida pelo próprio btop;
- 13 web apps em `~/.local/share/applications/`: criados pelo instalador;
- wrappers em `~/.local/bin` para claude, codex, copilot, crush, gemini, gh,
  ghui, grok, hunk, omp, opencode, pi e playwright: gerados pelo Omarchy;
- `~/.local/bin/playwright-cli`: resíduo antigo;
- `~/.config/BraveSoftware`, `~/.config/brave-flags.conf`: integração nativa,
  não perfil de usuário;
- tema `hackerman`, branding, autostart, `environment.d` e estado em
  `~/.local/state/omarchy/`;
- `~/.local/share/fonts/omarchy.ttf`: gerado por `omarchy font set`;
- caches, backups, históricos e perfis.

Os scripts, units e segredos de projetos pessoais que já têm repositório
próprio pertencem a esses repositórios. Não copiá-los para cá.

### 8.2 Pacotes deliberadamente excluídos

| pacote | razão |
|---|---|
| `neovim` | já vem via `omarchy-nvim` |
| `opera` | substituído pelo Brave |
| `vim` | sem uso relevante; nvim já existe |
| `zed`, `antigravity`, `cursor-bin` | sem uso recente e ocupam espaço |
| `nvm` | substituído pelo mise |
| `yq` | sem uso ou dependentes |
| `hyprvoice-bin` | substituído pelo voxtype |
| `nwg-displays` | gera formato que Omarchy 4 não lê |
| `slack-desktop`, `openvpn` | decisão do usuário |
| `nosqlbooster-mongodb`, `mongodb-tools` | decisão do usuário |
| `arduino-cli`, `arduino-ide-bin` | decisão do usuário |
| `jdownloader2`, `helvum` | decisão do usuário |

Não remover runtimes .NET existentes como parte deste projeto. O requisito é
garantir o SDK pelo mise, não limpar pacotes da máquina de origem.

### 8.3 Símbolos do `git_status` no starship

Usar os símbolos do Omarchy e preencher estados que ele deixa vazios:

| estado | codepoint | Nerd Font |
|---|---|---|
| staged | `U+EADC` | `diff-added` |
| deleted | `U+EADE` | `diff-removed` |
| renamed | `U+EADF` | `diff-renamed` |
| stashed | `U+EB4B` | `save` |

A fonte `ttf-jetbrains-mono-nerd` já vem no Omarchy. O símbolo de .NET é
`U+E77F`. Os separadores powerline usados pelo arquivo original incluem
`U+E0B6`, `U+E0B0` e `U+E0B4`.

### 8.4 Razões para não copiar a máquina inteira

A instalação de origem passou por nove meses de upgrades. Migrações adicionam e
substituem arquivos, mas nem sempre removem resíduos. Exemplos confirmados:

- tmux e nvim locais estão atrás dos defaults atuais;
- web apps possuem timestamp do instalador;
- a diferença do btop é apenas normalização de boolean;
- vários pacotes aparentemente pessoais vieram do batch inicial;
- wrappers locais foram gerados pelo `omarchy-mise-install`.

Portanto, existência e diferença local não provam intenção do usuário.

## 9. Checklist global de validação

### Automatizável com `HOME` temporário, fixtures e shims

### Estrutura e segurança

- [ ] Git reconhece o repositório e há commits incrementais.
- [ ] Todos os scripts passam em `bash -n`.
- [ ] Não há `/home/lfalcao` em arquivos portáveis.
- [ ] Não há tokens, chaves, credenciais, `.ovpn` ou estado de runtime.
- [ ] Somente um pacote `host-*` é aplicado por execução.
- [ ] Dry-run não altera arquivos, pacotes ou serviços.

### Idempotência

- [ ] Bootstrap executa duas vezes sem erro.
- [ ] Segunda execução não duplica linhas, plugins, extensões ou JSON.
- [ ] Stow não toma posse de arquivos gerenciados externamente.
- [ ] Merge do VS Code e tweaks produzem saída estável.

### Pós-aplicação, humana ou dependente do ambiente/hardware

### Ambiente de desenvolvimento

- [ ] `python`, venv e pip dentro do venv funcionam.
- [ ] Node 24, npm e pnpm 12 funcionam no zsh interativo.
- [ ] .NET SDK 10 suporta `dotnet new`, `build` e `run`.
- [ ] VS Code possui extensões de Python, JS/TS e C#.
- [ ] O módulo dotnet aparece corretamente no starship.

### Desktop e shell

- [ ] oh-my-zsh, autosuggestions, syntax highlighting, fzf, zoxide e mise carregam.
- [ ] Home, End, Delete, PageUp, PageDown, Ctrl+setas, Ctrl+Delete,
  Alt+Backspace, histórico por prefixo, Tab e Ctrl-R funcionam.
- [ ] Repetir os testes de teclas dentro de tmux e SSH.
- [ ] Hyprland recarrega sem `configerrors`.
- [ ] Acer opera em 165 Hz e workspaces 1–5 estão nele.
- [ ] Workspaces 6–10 estão na segunda tela do notebook.
- [ ] Depois da captura pendente, workspaces 6–10 estão na segunda tela do
  desktop; até lá, o `host.lua` desktop é um no-op Lua válido.
- [ ] Regras de janela e comportamento `silent` foram validados.
- [ ] Kanata está ativo apenas no notebook.

## 10. Pendências reais

Estas são as únicas informações ainda não resolvidas; não confundir com decisões
já fechadas:

1. O segundo monitor do desktop ainda não teve descrição EDID, modo e posição
   capturados. Isso bloqueia apenas sua configuração física e a fixação dos
   workspaces 6–10, não a estrutura, os testes automatizados nem um fluxo de
   bootstrap desktop válido com `host.lua` no-op.
2. A classe real do DBeaver deve ser confirmada com `hyprctl clients`; a regra
   proposta usa `^([dD][bB]eaver)$` com base no `StartupWMClass`. Isso bloqueia
   apenas a aceitação humana dessa regra, não os testes automatizados.

Qualquer nova pendência descoberta deve ser registrada aqui com impacto e forma
de validação. Não usar esta seção como diário de decisões concluídas.
