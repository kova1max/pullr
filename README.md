# pullr

[![CI](https://github.com/kova1max/pullr/actions/workflows/ci.yml/badge.svg)](https://github.com/kova1max/pullr/actions/workflows/ci.yml)
[![npm](https://img.shields.io/npm/v/%40kova1%2Fpullr?logo=npm&label=npm)](https://www.npmjs.com/package/@kova1/pullr)
[![Homebrew](https://img.shields.io/github/v/release/kova1max/pullr?logo=homebrew&label=homebrew)](https://github.com/kova1max/homebrew-tap)
[![License: MIT](https://img.shields.io/github/license/kova1max/pullr)](LICENSE)

Safe, fast-forward pull every git repository under a directory.

Built for workspaces made of many independent repositories, where keeping
everything current means `cd`-ing into each one.

```console
$ pullr ~/work
+ api (main, 3 new commits)
= web (main)
~ docs (main, 2 commits held back by local changes)
- scratch (main has no upstream)
x infra (main)
    diverged from upstream (behind 2, ahead 1): cannot fast-forward

Repos: 5  updated: 1  up to date: 1  dirty: 1  skipped: 1  failed: 1
Dirty: docs
Failed: infra
```

## Install

```sh
# Homebrew
brew install kova1max/tap/pullr

# npm
npm install -g @kova1/pullr
```

To try it without installing anything:

```sh
npx @kova1/pullr --dry-run ~/work
```

Every release is also mirrored to
[GitHub Packages](https://github.com/kova1max/pullr/pkgs/npm/pullr) as
`@kova1max/pullr` (GitHub requires the repo owner as scope). Installing from
there needs a GitHub token, so the npm registry above is the easier choice.

## What it will never do

pullr is built to be safe to run across a whole workspace without looking
first. It will never:

- **Create a merge commit.** Pulls are fast-forward only.
- **Touch a branch that has diverged** from its upstream. It is reported as
  failed and left exactly as it was. Rebasing it is opt-in with `--rebase`,
  and a rebase that hits a conflict is aborted, leaving the repository as it
  was.
- **Stash, overwrite or discard your changes.** There is no auto-stash. If
  local edits or untracked files are in the way of incoming changes, the
  repository is reported as dirty and left as it was; edits that don't touch
  incoming files don't stop the update.
- **Touch a repository on a detached `HEAD`**, or a branch with no upstream.
  Both are skipped.
- **Enter a nested repository.** Repositories inside another repository,
  including submodules, are left to their parent.
- **Follow symlinked directories.**

## Usage

```
pullr [options] [DIR]
```

| Option&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Default | Meaning |
| :--- | :--- | :--- |
| `DIR` | current&nbsp;directory | Where to look for repositories |
| `-j`, `--jobs N` | `8` | Work on up to `N` repositories in parallel. Output is buffered per repository and printed in discovery order, so it reads the same as a sequential run. With `N > 1` git never prompts for credentials; use `--jobs 1` for repositories that need an interactive login. |
| `--max-depth N` | `2` | How many directory levels below `DIR` to search. `0` = only `DIR` itself, `1` = `DIR` and its direct children, ... |
| `-n`, `--dry-run` | | Show what a run would do without pulling, see below |
| `-r`, `--rebase` | off | Rebase local commits onto the upstream instead of refusing a diverged branch (`git pull --rebase`). A rebase that hits a conflict is aborted and the repository is left as it was. |
| `--no-color` | | Disable colored output. Also disabled when the [`NO_COLOR`](https://no-color.org) environment variable is set, or when output is not a terminal. |
| `-V`, `--version` | | Print the version |
| `-h`, `--help` | | Show help |

### Output

Each repository gets one line: `+` updated, `=` already up to date, `~`
dirty (local changes are in the way of the update, which is held back), `-`
skipped, `x` failed (with the reason indented below it). Exits `1` if any
pull failed, `2` on invalid arguments, `0` otherwise; a dirty repository is
not a failure.

### Dry run

`pullr --dry-run` shows what a run would do, without pulling:

```console
$ pullr --dry-run ~/work
Dry run: nothing will be pulled.
+ api (main, 3 new commits)
= web (main)
x infra (main)
    diverged from upstream (behind 2, ahead 1): cannot fast-forward
- scratch (main has no upstream)

Repos: 4  would update: 1  up to date: 1  dirty: 0  skipped: 1  would fail: 1
Failed: infra
```

It runs `git fetch` in each repository first, so the answer reflects the
remote as it is now, then prints the same lines a real run would (with
`--rebase`, a diverged repository shows as `+ ... , 2 to rebase` instead of
`x`; whether the rebase would conflict is only known by running it). Fetching
only updates remote-tracking refs: the working tree and current branch are
never modified. Exit codes match a real run.

## How it compares

| | pullr | [gita](https://github.com/nosarthur/gita) | [gitup](https://github.com/earwig/git-repo-updater) | [myrepos](https://myrepos.branchable.com) (`mr`) | [mani](https://github.com/alajmo/mani) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Needs | bash and git | Python&nbsp;3.8+ | Python&nbsp;3.10+ | Perl | Go binary |
| Finds repos | scans a directory | register first (`gita add`) | scans a directory | register first (`~/.mrconfig`) | register first (`mani.yaml`) |
| Pulls in parallel | 8 at a time by default | all at once, no limit | no | opt-in | opt-in |
| Update | fetch + fast&#8209;forward | `git pull` | fetch + fast&#8209;forward | `git pull` | no built-in pull |
| Merge commits | never | depends on your git config | never | depends on your git config | depends on your command |
| Local changes in the way | reported as dirty | git's error | skipped | git's error | - |
| Dry run | yes | no | no | no | prints commands |

**Why "8 at a time" and not "all at once".** Many self-hosted git servers
limit how many SSH connections can be opening at the same time; OpenSSH's
default (`MaxStartups 10:30:100`) starts refusing them past 10. Fetching
every repository at once then fails for reasons that have nothing to do with
your repositories. On a self-hosted GitLab with 61 repositories, 16 parallel
fetches produced 6-9 of those spurious failures and 32 produced 10-14, while
8 produced none. GitHub itself handled 64 at once without errors, so raise
`-j` freely there.

## License

[MIT](LICENSE)
