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
4. Instale as duas dependências do próprio bootstrap:

   ```bash
   ./bootstrap.sh notebook --only 00-preflight
   ```

   O módulo valida o ambiente Omarchy e a rede, e instala Git e Stow se
   faltarem. Ele vem antes do dry-run porque o dry-run só consegue validar o
   que já está instalado.

5. Revise o plano sem alterar a máquina:

   ```bash
   ./bootstrap.sh notebook --dry-run
   # ou
   ./bootstrap.sh desktop --dry-run
   ```

6. Execute o bootstrap real para o host correto somente depois de revisar o
   dry-run:

   ```bash
   ./bootstrap.sh notebook
   # ou
   ./bootstrap.sh desktop
   ```

7. Rode o dry-run de novo. Essa é a passada que realmente valida: com tudo
   instalado, ele lê os arquivos de verdade e deve terminar com uma linha só.

   ```bash
   ./bootstrap.sh notebook --dry-run
   ```

   ```text
     nada a fazer: a máquina já está convergida.
   ```

A execução real para duas vezes pedindo senha: o `00-preflight` roda `sudo -v`
e o `40-shell` roda `chsh` para trocar o shell padrão para o zsh, que pede a
senha do próprio usuário. O dry-run não pede nenhuma das duas.

### resumo final do dry-run

Toda execução com `--dry-run` termina com um veredito. Ele só fala quando há o
que dizer:

```text
  atenção antes de aplicar:
    30-stow-omarchy  5 conflito(s) seriam movidos para backup
    55-tweaks        5 validações adiadas: alacritty.toml, foot.ini, ...

  24 mudanças planejadas; nada bloqueia.
```

O bloco `atenção antes de aplicar` lista duas coisas: conflitos, que são
arquivos seus que iriam para o backup, e validações adiadas, que são checagens
impossíveis até outro módulo rodar. `nada bloqueia` significa que nenhuma
verificação reprovou; uma reprovação aborta a execução e não chega no resumo.

A contagem não é o número de comandos que seriam executados. Cada módulo sonda
o estado atual por meios somente leitura antes de contar: `pacman -Qq`,
`git config --get`, `systemctl is-enabled`, `code --list-extensions`,
`mise ls --global --json` e comparação byte a byte dos arquivos que seriam
reescritos. Só entra na conta o que realmente mudaria.

Numa máquina convergida o resumo vira uma linha:

```text
  nada a fazer: a máquina já está convergida.
```

Ler o log inteiro continua sendo opcional; o resumo é a resposta para "posso
seguir a vida".

### o que o dry-run valida

Aborta a execução, independente do estado da máquina: ambiente que não é
Omarchy com base Arch, rede indisponível, host ou `--only` desconhecido, entrada
de pacote malformada, conflito de Stow que é diretório não gerenciado, destino
que resolve para dentro do pacote versionado, `settings.json` do VS Code que é
symlink ou JSON inválido, `~/.oh-my-zsh` que existe mas não é repositório Git, e
config de terminal cujo formato de fonte não bate com o esperado.

Só imprime o plano, sem conferir: nomes de pacote nos repositórios, IDs de
extensão do VS Code, versões do mise e a troca de shell.

Com a ferramenta presente, duas verificações rodam de verdade sem escrever no
disco: `stow -n`, que simula o plano de links e falha se o Stow recusaria os
argumentos, e `kanata --check`, que valida a sintaxe de
`stow/host-notebook/.config/kanata/config.kbd`. A simulação do Stow é pulada
quando há conflitos pendentes, já que a execução real os protegeria antes.

Numa máquina recém-instalada, cada ferramenta ausente aparece como
`ainda não existe` com o módulo que a instala, entra no resumo como validação
adiada, e o dry-run segue até o fim em vez de abortar. Nesse estado ele é mais um plano do que uma validação, o que é o
motivo da passada final do passo 7.

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
