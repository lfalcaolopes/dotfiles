# Manual de instalação e validação

Este repositório configura uma instalação limpa do Omarchy 4. O host deve ser
informado explicitamente: `notebook` inclui Kanata e a tela interna; `desktop`
mantém o segundo monitor como pendência documentada.

## 1. preparar a máquina

1. Conclua a instalação limpa do Omarchy.
2. Instale o Brave e defina-o como navegador padrão antes de clonar, se isso
   ainda não foi feito:

   ```bash
   omarchy install browser brave
   xdg-settings set default-web-browser brave-browser.desktop
   ```

3. Clone este repositório.
4. Revise o plano sem alterar a máquina:

   ```bash
   ./bootstrap.sh notebook --dry-run
   # ou
   ./bootstrap.sh desktop --dry-run
   ```

5. Execute o bootstrap real para o host correto somente depois de revisar o
   dry-run:

   ```bash
   ./bootstrap.sh notebook
   # ou
   ./bootstrap.sh desktop
   ```

A execução real para duas vezes pedindo senha: o `00-preflight` roda `sudo -v`
e o `40-shell` roda `chsh` para trocar o shell padrão para o zsh, que pede a
senha do próprio usuário. O dry-run não pede nenhuma das duas.

O bootstrap não oferece troca automática de host. Para trocar um host já
aplicado, remova primeiro os links da camada antiga com
`stow -D -d stow -t "$HOME" host-<host-antigo>` e só então execute o novo
bootstrap.

### adoção segura da máquina de origem

Os módulos Stow tratam arquivos regulares e links conflitantes como dados do
usuário. Eles copiam cada folha para
`${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<timestamp>/`, verificam
a cópia e só depois instalam o link gerenciado. Diretórios com conteúdo local
fazem o processo abortar; `stow --adopt` nunca é usado.

Na máquina de origem:

1. execute primeiro o dry-run e confira cada linha `proteger conflito`;
2. confirme que o diretório de backup não resolve para dentro deste
   repositório;
3. execute o bootstrap e guarde o caminho de backup exibido;
4. compare os arquivos protegidos antes de removê-los;
5. confira `git status` para garantir que nenhum arquivo versionado foi
   reescrito.

### settings.json do VS Code

O arquivo instalado tem duas partes, separadas por uma sentinela em comentário:

```jsonc
  "workbench.iconTheme": "material-icon-theme",

  // ==========================================================================
  // dotfiles:local
  // ...
  // ==========================================================================

  "workbench.colorTheme": "Hackerman"
}
```

Acima da sentinela fica a cópia literal de `config/vscode/settings.json`, com
os comentários e a ordem do repositório preservados. Esse bloco é reescrito por
inteiro a cada execução, então editar ali pela interface do VS Code não
persiste; o módulo registra `chave gerenciada divergente` antes de sobrescrever.

Abaixo da sentinela ficam as preferências desta máquina, como o tema e as
chaves que extensões injetam sozinhas. Elas sobrevivem entre execuções. Quando
uma dessas chaves passa a ser gerenciada pelo repositório, ela é removida do
bloco local para não duplicar.

Remover uma chave de `config/vscode/settings.json` a remove do arquivo
instalado na execução seguinte. Na primeira execução, antes de a sentinela
existir, toda chave que não esteja no repositório é tratada como local.

O módulo recusa um `settings.json` que seja symlink, para evitar escrever no
alvo do link.

## 2. autenticar serviços

Conclua os logins que não podem ser automatizados:

- GitHub, com `gh auth login`;
- Slack, Signal, Steam, Docker Hub e o perfil do navegador;
- perfil secundário do Claude, com `claude-dio` e depois `/login`.

O repositório não armazena tokens, `hosts.yml`, perfis de navegador nem
arquivos de credenciais do Claude.

## 3. criar chaves pessoais

Gere uma chave SSH nova na máquina e registre a chave pública no GitHub. Não
copie `~/.ssh` da instalação anterior para o repositório.

Importe uma chave GPG por canal seguro somente se a assinatura ou a
descriptografia com a identidade antiga ainda for necessária. Chaves SSH e GPG
continuam fora dos dotfiles.

## 4. instalar componentes interativos

1. Instale o 1Password pelo menu do Omarchy.
2. Se desejar ditado, instale o voxtype com:

   ```bash
   omarchy-voxtype-install
   ```

3. Transfira arquivos VPN por um canal seguro e recrie aliases ou comandos
   locais fora deste repositório. Arquivos `.ovpn` e credenciais não são
   versionados.
4. Aplique o tema built-in:

   ```bash
   omarchy theme set hackerman
   ```

O tema do VS Code fica local. O bootstrap não gerencia
`workbench.colorTheme`, e as extensões de tema continuam sob responsabilidade
do Omarchy.

## 5. validar shell e linguagens

Abra um novo terminal e verifique:

```bash
zsh -i -c 'node --version'
zsh -i -c 'npm --version'
zsh -i -c 'pnpm --version'
zsh -i -c 'dotnet --version'
dotnet new --list
python -m venv /tmp/dotfiles-venv-check
```

Node deve estar na linha 24, pnpm na 12 e o SDK .NET na 10. Python vem do
sistema; use ambientes virtuais para pacotes de projeto e `pipx` para CLIs.

Confirme também oh-my-zsh, autosuggestions, syntax highlighting, mise,
starship, zoxide e fzf. Teste Home, End, Delete, PageUp, PageDown, Ctrl+setas,
Ctrl+Delete, Alt+Backspace, histórico por prefixo, Tab e Ctrl-R. Repita as
teclas dentro de tmux e de uma sessão SSH.

## 6. validar desktop, janelas e Kanata

Após entrar numa sessão gráfica, execute:

```bash
hyprctl reload
hyprctl configerrors
hyprctl monitors all
hyprctl clients
```

Confirme os seguintes pontos:

- nenhum erro de configuração do Hyprland;
- Acer QG241Y P operando próximo de 165 Hz e com workspaces 1–5;
- no notebook, `eDP-1` com workspaces 6–10;
- Brave, Code, DBeaver, Postman, Steam e WhatsApp nos workspaces definidos;
- classe real do DBeaver. A regra atual usa `^([dD][bB]eaver)$`, inferida de
  `StartupWMClass`, e precisa ser confirmada em `hyprctl clients`;
- no notebook, `systemctl --user status kanata.service` e o comportamento
  físico das teclas: Caps toca Escape e, mantido, abre a camada de navegação
  com as setas em `hjkl`; Caps+Space aplica Caps Lock; Space não ativa camada
  alguma; os home row mods de `asdf` e `jkl;` respondem sem esperar o timeout
  um do outro.

O modificador `silent` pode abrir aplicativos em workspaces não visíveis
quando o notebook estiver usando somente um monitor. Esse comportamento é
esperado.

Kanata não é instalado nem habilitado pelo fluxo `desktop`.

### pendência do desktop

O arquivo `stow/host-desktop/.config/hypr/host.lua` é atualmente um no-op Lua
válido. No hardware desktop, capture com `hyprctl monitors all` a descrição
EDID, o modo, a posição e o refresh rate da segunda tela. Depois, complete o
arquivo com o monitor e fixe nele os workspaces 6–10. Não invente um conector
nem reutilize a identificação do notebook.

Essa pendência limita somente a segunda tela e os workspaces 6–10 do desktop.
O restante do bootstrap desktop pode ser aplicado e validado.

## 7. validar aplicativos e arquivos locais

Abra o VS Code e confira as extensões de Python, JavaScript/TypeScript e C#,
além do tema local preservado. Abra DBeaver, Postman, Steam, Slack e Signal
para concluir qualquer migração interna solicitada pelos próprios aplicativos.

Os logins, o hardware, as teclas, as regras de janela, a classe DBeaver e o
funcionamento físico do Kanata são verificações humanas. A suíte automatizada
usa apenas `HOME` temporário e shims; ela não substitui esta seção.
