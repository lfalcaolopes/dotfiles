# Run 1 — endurecer o plano e proteger o repositório

Trabalhe no repositório de dotfiles atual. Leia `SPEC.md` integralmente antes de
agir e trate suas decisões fechadas como requisitos. Esta run deve consolidar o
contrato de implementação e concluir a Fase 0; não implemente ainda os módulos
do bootstrap e não altere configurações da máquina em `$HOME`.

Como o trabalho envolve configuração de Omarchy, use a skill `omarchy` e leia
as referências pertinentes. Preserve `/usr/share/omarchy` estritamente como
fonte somente para leitura.

Objetivos:

1. Inspecionar o diretório, inclusive o `.git` vazio, sem presumir que já seja
   um repositório válido.
2. Inicializar o Git, criar um `.gitignore` conservador e registrar o `SPEC.md`
   original em um primeiro commit antes de qualquer captura de configuração.
3. Revisar e editar `SPEC.md` para resolver explicitamente estas lacunas:
   - definir como a máquina de origem, que já possui arquivos regulares nos
     destinos do Stow, será migrada com backup e sem usar `stow --adopt`;
   - separar "fluxo desktop válido" de "segundo monitor desktop concluído": o
     `host.lua` provisório deve ser Lua válida e no-op, e a configuração física
     continuará pendente até a captura do EDID/modo/posição;
   - fixar os valores aceitos por `--only` (prefira o basename do módulo, como
     `10-packages`, sem `.sh`) e exigir que cada módulo valide suas próprias
     dependências quando executado isoladamente;
   - declarar que `--dry-run` não pode chamar comandos mutáveis, incluindo
     `sudo -v`, gerenciadores de pacotes, clones/pulls, `chsh`, `systemctl`,
     instalação de extensões ou `mise use`;
   - definir testes com `HOME` temporário, fixtures e shims de comandos para
     validar sem modificar a estação de trabalho;
   - distinguir testes automatizáveis de verificações humanas ou dependentes
     de hardware.
4. Verificar se há outras contradições entre missão, critérios de aceite,
   pendências e teste final. Faça apenas os ajustes mínimos necessários; não
   reabra as decisões da seção 7 sem evidência nova.
5. Criar um segundo commit contendo o endurecimento do plano.

Restrições:

- Não copie ainda conteúdo de `~/.config`, `~/.claude` ou outros arquivos do
  usuário.
- Não instale pacotes, não use sudo, não recarregue Hyprland e não inicie ou
  habilite serviços.
- Preserve qualquer alteração preexistente que não pertença a esta tarefa.
- Não inclua segredos, dumps de ambiente ou estado local nos commits.

Critérios de aceite:

- `git status` funciona e está limpo ao final, salvo impedimento devidamente
  explicado.
- Existem pelo menos o commit do plano original e o commit da revisão.
- A estratégia de adoção pelo Stow, o contrato de dry-run, `--only`, testes e
  o status incompleto do desktop estão inequívocos no `SPEC.md`.
- Nenhum arquivo fora do repositório foi alterado.

Ao finalizar, relate os commits, os ajustes de contrato feitos, os testes
executados e qualquer bloqueio real para a Run 2.
