# Run 5 — aplicar e validar no notebook real

Trabalhe no repositório de dotfiles atual e conclua a aplicação controlada no
host `notebook`. Leia `SPEC.md` e `docs/MANUAL.md` integralmente, revise os
commits e confirme que a Run 4 declarou o repositório pronto. Use a skill
`omarchy` e os guias aplicáveis antes de modificar ou recarregar configurações
do desktop.

Esta run está autorizada a executar o bootstrap no notebook e, mediante os
mecanismos normais de aprovação do ambiente, realizar as mutações previstas na
spec. Não amplie o escopo para autenticações, segredos ou passos manuais.

Sequência obrigatória:

1. Confirmar host, versão do Omarchy/Arch, branch/worktree, commits esperados e
   ausência de alterações não relacionadas. Não descarte mudanças do usuário.
2. Executar novamente toda a suíte automatizada e os parsers antes de tocar no
   sistema.
3. Executar `./bootstrap.sh notebook --dry-run`, revisar a saída e confirmar
   que ela não alterou arquivos, pacotes, serviços, shell ou configuração mise.
4. Inventariar os destinos Stow e demais arquivos que serão modificados. Seguir
   exatamente a estratégia de adoção definida na spec:
   - criar backup recuperável fora do repositório;
   - nunca usar `stow --adopt`;
   - substituir automaticamente apenas arquivos comprovadamente idênticos ao
     conteúdo versionado;
   - diante de diferença não prevista ou risco de perda, parar e pedir decisão
     do usuário antes de sobrescrever.
5. Solicitar as aprovações necessárias e executar `./bootstrap.sh notebook`.
   Não contorne prompts de privilégio nem exponha credenciais.
6. Validar imediatamente erros de cada módulo. Para Hyprland, executar
   `hyprctl reload` e depois `hyprctl configerrors`, corrigindo problemas e
   repetindo a validação até ficar limpa ou existir bloqueio real.
7. Executar as verificações automatizáveis da seção 9: Bash, segurança, links
   Stow, serviço Kanata, Git, VS Code, shell, Python/venv, Node 24, npm, pnpm 12,
   .NET SDK 10 e demais checks aplicáveis.
8. Registrar hashes/estado dos arquivos gerenciados relevantes, executar o
   bootstrap completo uma segunda vez e provar idempotência: sem duplicações,
   conflitos ou mudanças inesperadas de bytes.
9. Repetir `hyprctl reload`/`hyprctl configerrors` depois da segunda execução e
   verificar via `hyprctl monitors` o Acer a aproximadamente 165 Hz e a
   distribuição de workspaces do notebook.
10. Fazer somente as verificações visuais que puderem ser observadas com
    segurança. Não alegar que teclas, tmux/SSH, classes de janelas ou UX foram
    validados sem observação real; liste esses itens para confirmação humana.
11. Atualizar apenas a documentação ou testes se a execução revelar uma
    pré-condição reproduzível. Faça commit dessas correções, mas não versione
    logs, backups ou estado da máquina.

Restrições:

- Não executar autenticações (`gh`, gcloud, Docker, Claude etc.), importar
  chaves, copiar VPNs ou instalar itens manuais.
- Não executar o fluxo desktop nem inventar dados do segundo monitor.
- Não remover arquivos divergentes ou dados materiais sem confirmação.
- Não editar `/usr/share/omarchy`.
- Não usar comandos destrutivos para forçar um estado limpo.
- Se uma etapa exigir interação humana impossível nesta run, avance nas demais
  verificações seguras e reporte-a como pendente.

Critérios de aceite:

- O bootstrap notebook completa duas vezes sem erro.
- A segunda execução é convergente e não duplica configuração.
- `hyprctl configerrors` fica vazio.
- Kanata está habilitado/ativo somente no notebook.
- Node 24, pnpm 12, .NET SDK 10 e Python venv funcionam.
- Não foram versionados segredos, backups ou estado local.
- Verificações manuais restantes e a pendência do monitor desktop estão
  claramente documentadas, sem falsa declaração de conclusão.

Ao finalizar, entregue o estado final, comandos/testes executados, mudanças
observadas entre primeira e segunda execução, localização do backup e como
restaurá-lo, commits adicionais e checklist exato do que ainda depende do
usuário ou do desktop.
