# dotfiles

Idempotent bootstrap for a fresh [Omarchy](https://omarchy.org) 4 install. One
command takes a new machine to a configured one. No Omarchy defaults copied, no
runtime state dragged over from the old box.

```bash
git clone https://github.com/lfalcaolopes/dotfiles.git
cd dotfiles
./bootstrap.sh notebook --only 00-preflight   # installs git and stow
./bootstrap.sh notebook --dry-run             # review
./bootstrap.sh notebook                       # apply
./bootstrap.sh notebook --dry-run             # confirm nothing is left to do
```

The preflight step comes first because `--dry-run` can only check what is
already installed. With Stow present it simulates the symlink plan (`stow -n`)
instead of just printing the command. Skipping it still works: the dry run
reports each missing tool as `ainda não existe` and plans the rest.

The last dry run is the real check. Every run ends with a verdict that only
speaks up when something needs you, both in dry run and after applying:

```text
  atenção antes de aplicar:
    30-stow-omarchy  5 conflito(s) seriam movidos para backup
    55-tweaks        5 validações adiadas: alacritty.toml, foot.ini, ...

  24 mudanças planejadas; nada bloqueia.
```

On a converged machine it collapses to one line, which is what makes the run
idempotent:

```text
  nada a fazer: a máquina já está convergida.
```

A real run ends the same way, in the past tense: `atenção depois de aplicar`
for what is left for you to do by hand (reload the session, log back into a
webapp, look at the backup directory), then `N mudanças aplicadas.`, or
`nada a fazer: a máquina já estava convergida.` when nothing changed.

The count is not a tally of commands. Each module probes the current state
read-only first (`pacman -Qq`, `git config --get`, `systemctl is-active`,
`code --list-extensions`, `mise ls --global`, byte comparison of the files it
would rewrite), so it counts only what would actually change.

Host is a required argument, not detected from the hostname. `notebook` has the
internal panel and Kanata; `desktop` has two monitors and no Kanata.

## layout

```text
bootstrap.sh          runs the modules in order
modules/              one step per file, each runnable on its own
lib/common.sh         logging, Stow with backup, dry-run
packages/             package and extension lists
config/               applied by copy or merge, never linked
stow/common/          portable config for any Linux
stow/omarchy/         Omarchy overrides
stow/host-<name>/     per-host monitor and hardware
docs/MANUAL.md        the steps that need a human
SPEC.md               full plan and the reasoning behind it
```

## what the tests cover

`tests/run.sh` uses a temp `HOME` and `PATH` shims, so it never touches the real
machine. It checks:

- `--dry-run` prints everything and mutates nothing: no `sudo -v`, no package
  manager, no `chsh`, no `systemctl`. Only read-only probes run: `stow -n` and
  `kanata --check`.
- `--dry-run` completes on a machine where nothing is installed yet, and aborts
  when a probe fails, such as an invalid Kanata config.
- A fully converged fixture ends with `nada a fazer`, in dry run and in a real
  run, and the same fixture with one runtime off its pin and one conflicting
  file reports both.
- A real run counts what it changed and prints what the person still has to do,
  such as the `hyprctl reload` a keyboard change needs.
- Re-running converges instead of duplicating config.
- An existing file that collides with a managed file gets copied to
  `~/.local/state/dotfiles/backups/<timestamp>/` and verified before the symlink
  replaces it. `stow --adopt` is never used, and a directory with local content
  aborts the run instead of being swallowed.

## what is not here

No secrets, tokens, keys, browser profiles, or history. `~/.ssh`, `~/.gnupg`,
`hosts.yml`, and credentials are excluded by rule. Files that Omarchy, `gh`,
`mise`, VS Code, or systemd rewrite on their own are set by command or merge, so
they never become symlinks.

Logins, personal keys, and the 1Password and voxtype installs are in
[`docs/MANUAL.md`](docs/MANUAL.md). Every run ends by listing the ones a
read-only probe still finds undone, so the checklist is on screen instead of
only in the docs.

## license

MIT.
