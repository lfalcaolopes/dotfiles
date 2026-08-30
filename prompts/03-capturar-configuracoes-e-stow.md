# Run 3 — capturar configurações e implementar as camadas Stow

Trabalhe no repositório de dotfiles atual. Leia `SPEC.md` integralmente, revise
os commits anteriores e confirme os critérios das Runs 1 e 2. Use a skill
`omarchy` e leia integralmente os guias de Hyprland aplicáveis antes de criar
overrides.

Implemente as Fases 3 e 4: configuração comum, overrides do Omarchy e camadas de
host. Capture somente preferências declaradas e mantenha a máquina de origem
inalterada nesta run.

Objetivos:

1. Comparar cada arquivo candidato com os defaults atuais do Omarchy em
   `/usr/share/omarchy` e com as regras de ownership/exclusão da spec antes de
   copiá-lo. Nunca edite `/usr/share/omarchy`.
2. Popular `stow/common` apenas com os itens autorizados, adaptando caminhos
   para serem portáveis e removendo conteúdo rejeitado.
3. Construir `.zshrc`, `starship.toml`, Git ignore, Claude Code,
   `hypr-close-window` e keybindings exatamente conforme a spec.
4. Fazer uma revisão explícita de segurança dos arquivos capturados: procurar
   tokens, chaves, credenciais, caminhos absolutos do usuário, arquivos de
   VPN, históricos e estado local. Não imprimir valores sensíveis no relatório.
5. Popular `stow/omarchy` com overrides mínimos, não cópias indiscriminadas dos
   defaults.
6. Antes de escrever regras de janela, consultar a documentação oficial vigente
   do Hyprland sobre Window Rules e conferir os helpers atuais do Omarchy em
   `$OMARCHY_PATH/default/hypr/windows.lua`. Use somente fontes oficiais para
   essa verificação técnica.
7. Criar `host-notebook` com `host.lua` e somente os arquivos Kanata aprovados,
   excluindo o `.git` interno.
8. Criar `host-desktop/host.lua` como Lua válida, explicitamente no-op e com a
   pendência do segundo monitor documentada; não inventar conector, EDID, modo
   ou posição.
9. Implementar os módulos Stow `20`, `30` e `35`, incluindo validação de conflito
   e dry-run. Não aplicar Stow no `$HOME` real.
10. Validar sintaxe Lua, TOML/JSON quando houver ferramentas disponíveis,
    codepoints obrigatórios do Starship, Bash e segurança. Testar Stow somente
    contra um `HOME` temporário representando uma instalação limpa.
11. Fazer commits incrementais coerentes.

Restrições:

- Não executar `stow` contra o `$HOME` real, `hyprctl reload`, instalação de
  pacotes, mudança de shell ou serviços.
- Não usar `stow --adopt`.
- Não modificar configurações atuais enquanto as lê.
- Não versionar `.credentials.json`, `hosts.yml`, `.ssh`, `.gnupg`, `.ovpn`,
  `.claude.json`, caches, históricos ou perfis.
- Não presumir que existência ou diferença local implica intenção do usuário.
- Preserve alterações preexistentes que não pertençam à tarefa.

Critérios de aceite:

- Stow funciona sem conflitos no `HOME` temporário e aplica exatamente uma
  camada de host.
- Os arquivos Lua passam no parser adequado disponível.
- O Starship é válido e os glifos/codepoints exigidos são preservados.
- Não há `/home/lfalcao`, tokens ou credenciais em arquivos portáveis.
- `host-desktop/host.lua` é válido, seguro e explicitamente incompleto.
- Testes existentes continuam passando e o worktree termina limpo após commits.

Ao finalizar, relate os commits, fontes/defaults comparados, validações feitas,
itens deliberadamente não capturados e pendências para a Run 4. Não exponha
segredos encontrados durante a inspeção.
