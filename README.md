# dotfiles

Bootstrap idempotente para uma instalação limpa do [Omarchy](https://omarchy.org)
4. Um comando parte do sistema recém instalado e chega à estação configurada,
sem copiar defaults do Omarchy nem estado de runtime da máquina de origem.

Feito para os meus dois hosts. Serve como referência para quem usa Omarchy e
quiser a mesma estrutura, mas as preferências dentro dele são minhas.

```bash
git clone https://github.com/lfalcaolopes/dotfiles.git
cd dotfiles
./bootstrap.sh notebook --dry-run   # revisar
./bootstrap.sh notebook             # aplicar
```

O host é argumento obrigatório e não é detectado por hostname: `notebook` tem
painel interno e Kanata, `desktop` tem dois monitores e nenhum Kanata.

## como está organizado

```text
bootstrap.sh          orquestra os módulos na ordem
modules/              um passo por arquivo, executável isoladamente
lib/common.sh         logging, Stow com backup, dry-run
packages/             listas triadas de pacotes e extensões
config/               arquivos aplicados por cópia ou merge, nunca por link
stow/common/          configuração portável para qualquer Linux
stow/omarchy/         overrides do Omarchy
stow/host-<nome>/     monitor e hardware de um host
docs/MANUAL.md        os passos que exigem uma pessoa
SPEC.md               o plano completo e as decisões por trás dele
```

Três garantias que os testes em `tests/run.sh` cobrem, com `HOME` temporário e
shims no `PATH`, sem tocar na máquina real:

`--dry-run` descreve tudo e não executa um único comando mutável, nem `sudo -v`,
nem gerenciador de pacotes, nem `chsh`, nem `systemctl`.

Reexecutar converge para o mesmo estado em vez de duplicar configuração.

Arquivo seu que conflite com um arquivo gerenciado é copiado para
`~/.local/state/dotfiles/backups/<timestamp>/` e verificado antes de ser
substituído pelo link. `stow --adopt` nunca é usado, e um diretório com
conteúdo local aborta a execução em vez de ser absorvido.

## o que não está aqui

Nenhum segredo, token, chave, perfil de navegador ou histórico. `~/.ssh`,
`~/.gnupg`, `hosts.yml` e credenciais ficam fora por regra, não por descuido.
Arquivos que o Omarchy, o `gh`, o `mise`, o VS Code ou o systemd reescrevem
sozinhos são configurados por comando ou merge, nunca viram symlink.

Os logins, as chaves pessoais e a instalação do 1Password e do voxtype estão em
[`docs/MANUAL.md`](docs/MANUAL.md).

## licença

MIT. As preferências pessoais dentro dos arquivos são minhas; a estrutura é sua
para copiar.
