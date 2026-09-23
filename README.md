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
brew install kova1max/tap/pullr   # after that, plain `pullr` works too

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

Releases are cut by GitHub Actions, never from a laptop. Run the Release
workflow from the Actions tab, or:

```sh
gh workflow run release.yml -f bump=patch   # or minor / major
```

It runs as `github-actions[bot]` and:

1. bumps the version in `package.json` and `bin/pullr`, runs shellcheck and
   the tests, then commits `release vX.Y.Z` and tags it on `main`;
2. creates the GitHub release with notes generated from the changes since
   the previous tag;
3. publishes to npm via trusted publishing (OIDC, no token), with provenance
   (the very first publish uses a temporary `NPM_TOKEN` secret, since npm only
   allows trusted publishing for a package that already exists);
4. points the formula in
   [kova1max/homebrew-tap](https://github.com/kova1max/homebrew-tap) at the
   new tag, using the `TAP_DEPLOY_KEY` secret (a write deploy key on the tap);
5. installs from npm and from the tap to verify both.

## License

[MIT](LICENSE)
