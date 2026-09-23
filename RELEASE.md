# Releasing pullr

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
3. publishes to npm via trusted publishing (OIDC, no token), with provenance;
4. points the formula in
   [kova1max/homebrew-tap](https://github.com/kova1max/homebrew-tap) at the
   new tag, using the `TAP_DEPLOY_KEY` secret (a write deploy key on the tap);
5. installs from npm and from the tap to verify both.
