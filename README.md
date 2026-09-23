# pullr

Fast-forward pull every git repository under a directory.

Built for workspaces made of many independent repositories, where keeping
everything current means `cd`-ing into each one.

```console
$ pullr ~/work
+ api (main, 3 new commit(s))
= web (main)
- scratch (main has no upstream)
x infra (main)
    fatal: Not possible to fast-forward, aborting.

Repos: 4  updated: 1  up to date: 1  skipped: 1  failed: 1
Failed: infra
```

## Install

```sh
# Homebrew
brew install kova1max/tap/pullr

# npm
npm install -g @kova1max/pullr
```

Or copy [`bin/pullr`](bin/pullr) anywhere on your `PATH` - it is a single bash
script with no dependencies beyond `git`.

## Usage

```
pullr [--max-depth N] [DIR]
```

| Option | Default | Meaning |
| --- | --- | --- |
| `DIR` | current directory | Where to look for repositories |
| `--max-depth N` | `2` | How many directory levels below `DIR` to search. `0` = only `DIR` itself, `1` = `DIR` and its direct children, ... |
| `-V`, `--version` | | Print the version |
| `-h`, `--help` | | Show help |

Behaviour:

- Runs `git pull --ff-only`, so it never creates merge commits. A branch that
  has diverged from its upstream is reported as failed and left untouched.
- Does not descend into a repository once found - nested repositories and
  submodules are left to their parent.
- Skips repositories on a detached `HEAD` and branches with no upstream.
- Does not follow symlinked directories.
- Exits `1` if any pull failed, `2` on invalid arguments, `0` otherwise.

Each repository gets one line: `+` updated, `=` already up to date, `-`
skipped, `x` failed (with git's output indented below it).

## Development

```sh
npm install     # installs bats
npm test        # end-to-end tests against real temporary git repos
npm run lint    # shellcheck
PULLR_BASH=/bin/bash npm test   # run the suite under macOS's bash 3.2
```

## Releasing

Releases are automated with
[release-please](https://github.com/googleapis/release-please) and driven by
[Conventional Commits](https://www.conventionalcommits.org/):

1. Merge commits such as `feat: ...` or `fix: ...` into `main`.
2. release-please keeps a release PR open that bumps the version and updates
   `CHANGELOG.md`.
3. Merging that PR tags `vX.Y.Z` and creates the GitHub release, then the
   release workflow:
   - publishes to npm via trusted publishing (OIDC, no token), with provenance;
   - points the formula in
     [kova1max/homebrew-tap](https://github.com/kova1max/homebrew-tap) at the
     new tag, using the `TAP_DEPLOY_KEY` secret (a write deploy key on the tap);
   - installs from npm and from the tap to verify both.

## License

[MIT](LICENSE)
