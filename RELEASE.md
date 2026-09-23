# Releasing pullr

Releases are cut by GitHub Actions, never from a laptop. Run the Release
workflow from the Actions tab, or:

```sh
gh workflow run release.yml -f bump=patch   # or minor / major
```

Optionally pass `-f notes="..."` (Markdown) to open the release notes with a
short summary; the generated list of pull requests follows it.

It runs as `github-actions[bot]` and:

1. bumps the version in `package.json` and `bin/pullr`, runs shellcheck and
   the tests, then commits `release vX.Y.Z` and tags it on `main`;
2. creates the GitHub release with notes generated from the pull requests
   merged since the previous tag, grouped by label as configured in
   `.github/release.yml` (changes pushed straight to `main` don't appear);
3. publishes to npm via trusted publishing (OIDC, no token), with provenance;
4. mirrors the same tarball to GitHub Packages as `@kova1max/pullr` (GitHub
   only accepts packages scoped to the repo owner), using the workflow's own
   `GITHUB_TOKEN`;
5. points the formula in
   [kova1max/homebrew-tap](https://github.com/kova1max/homebrew-tap) at the
   new tag, using the `TAP_DEPLOY_KEY` secret (a write deploy key on the tap);
6. installs from the tap on macOS to verify the formula. (npm is not re-checked:
   it can take over ten minutes to serve a new version.)
