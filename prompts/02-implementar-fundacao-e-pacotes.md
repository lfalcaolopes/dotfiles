# Run 2 — implementar fundação, orquestração e pacotes

Trabalhe no repositório de dotfiles atual. Leia `SPEC.md` integralmente e
confirme que os critérios da Run 1/Fase 0 estão cumpridos. Se houver divergência
entre este prompt e o plano endurecido, prevalece o `SPEC.md`; registre qualquer
incompatibilidade relevante antes de prosseguir.

Implemente as Fases 1 e 2: estrutura inicial, `bootstrap.sh`, `lib/common.sh`,
módulos de preflight/pacotes e listas de pacotes. Não instale pacotes nem aplique
configurações reais nesta run.

Objetivos:

1. Criar a árvore alvo da especificação sem placeholders desnecessários.
2. Implementar parsing de:
   - host obrigatório `notebook|desktop` descoberto de `stow/host-*`;
   - `--only <modulo>` conforme o contrato consolidado;
   - `--dry-run` rigorosamente não mutável.
3. Implementar execução ordenada, propagação de erro com identificação do
   módulo e independência do diretório atual.
4. Concentrar em `lib/common.sh` logging, verificação de comandos, criação de
   diretórios e demais utilitários definidos na spec, sem duplicação nos
   módulos.
5. Implementar `00-preflight.sh` e `10-packages.sh`, incluindo separação entre
   pacotes oficiais e AUR, ausência válida de lista do desktop e idempotência.
6. Criar exatamente as listas de pacotes da spec.
7. Criar testes automatizados para parsing, ordem, host/módulo inválido,
   execução fora da raiz, lista ausente e dry-run. Use `HOME` temporário e shims
   de `sudo`, `pacman`, `yay`, `git`, `stow` e outros comandos mutáveis; os
   testes devem falhar caso algum shim mutável seja chamado no dry-run.
8. Executar validações estáticas e registrar um commit incremental coerente.

Restrições:

- Não executar instalação real, `sudo`, `pacman -S`, `yay -S`, Stow sobre o
  `$HOME`, clones, serviços ou alterações de shell.
- Não capturar ainda arquivos pessoais da máquina de origem.
- Todo script Bash deve usar `set -Eeuo pipefail` e passar em `bash -n`.
- ShellCheck deve ser executado somente se estiver disponível; sua ausência
  não autoriza instalação nesta run.
- Preserve alterações preexistentes e não versionadas que não pertençam à
  tarefa.

Critérios de aceite:

- Sem host e com host/módulo inválido, o bootstrap falha antes de qualquer
  mutação.
- `--dry-run` percorre o plano inteiro usando shims sem realizar escrita ou
  chamar comandos mutáveis.
- `--only` executa exatamente um módulo e esse módulo valida dependências
  próprias.
- A ausência de `packages/host-desktop.txt` é aceita.
- Todos os scripts passam em `bash -n`; testes automatizados passam.
- O worktree termina limpo após commit, salvo impedimento explicado.

Ao finalizar, informe arquivos principais, commit, comandos de teste, cobertura
do dry-run e qualquer risco que a Run 3 precise considerar.
