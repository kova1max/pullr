# Contributing to pullr

Thanks for helping. Bug reports and feature ideas go in
[issues](https://github.com/kova1max/pullr/issues); the templates ask for what
is needed to act on them.

## Ground rules

pullr is a single bash script with no dependencies beyond `git`, and it is
built to be safe to run across a whole workspace without looking first. Keep
changes within those limits:

- Nothing it does by default may lose or rewrite work - see "What it will
  never do" in the [README](README.md). Riskier behaviour is opt-in.
- It must run on macOS's stock bash 3.2 as well as bash 5.
- Keep it one file: `bin/pullr`.

## Working on it

```sh
npm install                     # installs bats
npm test                        # end-to-end tests against real temporary git repos
PULLR_BASH=/bin/bash npm test   # the same suite under macOS's bash 3.2
npm run lint                    # shellcheck
```

Every change needs tests. The suite builds real repositories in a temporary
directory; see `test/pullr.bats` for the helpers.

## Pull requests

- One change per PR. CI runs shellcheck and the tests on Linux and macOS
  (bash 5 and 3.2).
- Add one label - `enhancement`, `bug`, `documentation`, `maintenance` or
  `breaking-change`. Release notes are generated from merged PRs and grouped
  by these labels, so the PR title is what users will read: write it for them.

## Releases

Releases are cut by the maintainer with GitHub Actions - see
[RELEASE.md](RELEASE.md).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
