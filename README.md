# dotfiles

Idempotent bootstrap for a fresh [Omarchy](https://omarchy.org) 4 install. One
command takes a new machine to a configured one. No Omarchy defaults copied, no
runtime state dragged over from the old box.

```bash
git clone https://github.com/lfalcaolopes/dotfiles.git
cd dotfiles
./bootstrap.sh notebook --dry-run   # review
./bootstrap.sh notebook             # apply
```

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
machine. It checks three things:

- `--dry-run` prints everything and mutates nothing: no `sudo -v`, no package
  manager, no `chsh`, no `systemctl`.
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
[`docs/MANUAL.md`](docs/MANUAL.md).

## license

MIT.
