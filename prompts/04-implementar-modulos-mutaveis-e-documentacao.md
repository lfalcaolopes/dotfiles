# Run 4 — implementar módulos mutáveis, documentação e ensaio completo

Trabalhe no repositório de dotfiles atual. Leia `SPEC.md` integralmente e
confirme os critérios das Runs 1–3. Use a skill `omarchy` e seus guias sobre
shell/idle, terminais e Hyprland quando aplicável. Esta run implementa as ações,
mas ainda não deve aplicá-las à estação de trabalho real.

Implemente as Fases 5, 6 e 7: shell, Kanata, VS Code, tweaks, mise,
documentação e validação automatizada completa.

Objetivos:

1. Implementar `40-shell.sh` com instalação/atualização idempotente e
   não interativa do oh-my-zsh/plugins, proteção de checkouts sujos, Git global,
   shell padrão e perfil secundário do Claude conforme a spec.
2. Implementar `45-kanata.sh` somente para notebook, copiando a unit em vez de
   symlinká-la e modelando `daemon-reload`, enable e restart de forma
   convergente.
3. Criar a unit Kanata da spec, sem caminhos pessoais ou credenciais.
4. Implementar `50-editors.sh` com merge JSON atômico e seguro, sem seguir
   symlink de destino, preservando chaves locais não gerenciadas e instalando a
   lista exata de extensões.
5. Implementar `55-tweaks.sh` com edições dirigidas e estáveis dos quatro
   terminais e de `~/.config/omarchy/shell.json`; falhar claramente se o formato
   esperado mudar.
6. Implementar `60-mise.sh` com as três linhas globais fechadas na spec.
7. Criar `docs/MANUAL.md` na ordem real de uso, incluindo adoção segura da
   máquina de origem, verificações humanas, DBeaver e pendência do desktop.
8. Expandir os testes com fixtures para:
   - checkout Git ausente, limpo e sujo;
   - unit copiada duas vezes;
   - merge de VS Code preservando chaves locais e recusando symlink;
   - tweaks executados duas vezes com resultado byte a byte idêntico;
   - desktop pulando Kanata;
   - versões/comandos mise corretos;
   - dry-run integral sem invocar nenhum comando mutável.
9. Executar `bash -n`, ShellCheck se disponível, parsers e a suíte completa.
10. Executar `./bootstrap.sh notebook --dry-run` e
    `./bootstrap.sh desktop --dry-run` com ambiente controlado. Não rode o
    bootstrap real.
11. Fazer commits incrementais coerentes.

Restrições:

- Não instalar pacotes ou extensões, não clonar/puxar repositórios reais, não
  executar `chsh`, `systemctl`, `mise use`, Stow no `$HOME` nem editar arquivos
  reais do usuário.
- Não recarregar Hyprland, terminal ou Omarchy Shell nesta run.
- Não alterar `/usr/share/omarchy`.
- Use shims e `HOME` temporário para todas as ações potencialmente mutáveis.
- Preserve alterações preexistentes não relacionadas.

Critérios de aceite:

- Todos os módulos estão implementados, são isoladamente executáveis e
  respeitam dry-run.
- Duas execuções sobre fixtures convergem para bytes idênticos onde aplicável.
- Merge do VS Code mantém `workbench.colorTheme` local e recusa destino
  symlinkado.
- Kanata só atua no notebook e sua unit é copiada.
- Dry-runs de notebook e desktop terminam com sucesso e sem mutações.
- Todos os testes automatizados passam e o worktree fica limpo após commits.

Ao finalizar, entregue um resumo dos commits, testes e limitações que só podem
ser verificadas ao vivo. Indique claramente se a Run 5 está segura para começar.
