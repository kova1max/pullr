#!/usr/bin/env bats
# End-to-end tests: build a real remote plus clones in a temp dir, run pullr.
# PULLR_BASH picks the interpreter, so CI can also cover macOS's bash 3.2.

setup() {
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  PULLR="$BATS_TEST_DIRNAME/../bin/pullr"
  cd "$BATS_TEST_TMPDIR"

  git init -q --bare -b main origin.git
  git clone -q origin.git seed 2>/dev/null
  git -C seed commit -q --allow-empty -m one
  git -C seed push -q origin main
  mkdir ws
}

pullr() {
  "${PULLR_BASH:-bash}" "$PULLR" "$@"
}

clone() {
  git clone -q origin.git "ws/$1" 2>/dev/null
}

advance_origin() {
  git -C seed commit -q --allow-empty -m two
  git -C seed commit -q --allow-empty -m three
  git -C seed push -q origin main
}

@test "fast-forwards a repo that is behind" {
  clone behind
  advance_origin
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ behind (main, 2 new commits)"* ]]
  [ "$(git -C ws/behind rev-parse HEAD)" = "$(git -C origin.git rev-parse main)" ]
}

@test "reports a repo that is already up to date" {
  clone current
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"= current (main)"* ]]
  [[ "$output" == *"up to date: 1"* ]]
}

@test "skips detached HEAD and branches without upstream" {
  clone detached
  git -C ws/detached checkout -q --detach
  git init -q -b main ws/local
  git -C ws/local commit -q --allow-empty -m x
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"- detached (detached HEAD)"* ]]
  [[ "$output" == *"- local (main has no upstream)"* ]]
  [[ "$output" == *"skipped: 2"* ]]
}

@test "fails a diverged repo without touching it, keeps going, exits 1" {
  clone diverged
  clone other
  git -C ws/diverged commit -q --allow-empty -m local
  local before
  before="$(git -C ws/diverged rev-parse HEAD)"
  advance_origin
  run pullr ws
  [ "$status" -eq 1 ]
  [[ "$output" == *"x diverged (main)"* ]]
  [[ "$output" == *"+ other (main, 2 new commits)"* ]]
  [[ "$output" == *"Failed: diverged"* ]]
  [ "$(git -C ws/diverged rev-parse HEAD)" = "$before" ]
}

@test "default max depth is 2" {
  mkdir -p ws/a/b
  clone a/two
  clone a/b/three
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"a/two"* ]]
  [[ "$output" != *"three"* ]]
}

@test "--max-depth reaches deeper repos, in both spellings" {
  mkdir -p ws/a/b
  clone a/b/three
  run pullr --max-depth 3 ws
  [[ "$output" == *"= a/b/three (main)"* ]]
  run pullr --max-depth=3 ws
  [[ "$output" == *"= a/b/three (main)"* ]]
}

@test "--max-depth 0 pulls only DIR itself" {
  clone self
  run pullr --max-depth 0 ws/self
  [ "$status" -eq 0 ]
  [[ "$output" == *"= . (main)"* ]]
}

@test "does not descend into a repository once found" {
  clone outer
  git init -q ws/outer/inner
  run pullr --max-depth 5 ws
  [ "$status" -eq 0 ]
  [[ "$output" != *"inner"* ]]
  [[ "$output" == *"Repos: 1"* ]]
}

@test "defaults to the current directory" {
  clone here
  cd ws
  run pullr
  [ "$status" -eq 0 ]
  [[ "$output" == *"= here (main)"* ]]
}

@test "reports when no repositories are found" {
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == "No git repositories found under "*" (max depth 2)" ]]
}

@test "rejects invalid arguments with exit 2" {
  run pullr --max-depth x
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-negative integer"* ]]
  run pullr --max-depth
  [ "$status" -eq 2 ]
  run pullr --nope
  [ "$status" -eq 2 ]
  run pullr ws ws
  [ "$status" -eq 2 ]
  run pullr does-not-exist
  [ "$status" -eq 2 ]
}

@test "--version prints the package.json version" {
  local expected
  expected="$(sed -n 's/.*"version": "\(.*\)".*/\1/p' "$BATS_TEST_DIRNAME/../package.json")"
  run pullr --version
  [ "$status" -eq 0 ]
  [ "$output" = "pullr $expected" ]
}

@test "reports a single new commit without a plural s" {
  clone one
  git -C seed commit -q --allow-empty -m two
  git -C seed push -q origin main
  run pullr ws
  [[ "$output" == *"+ one (main, 1 new commit)"* ]]
}

@test "--jobs keeps output in discovery order and totals identical" {
  clone a-behind; clone b-current; clone c-diverged; clone d-behind
  git -C ws/c-diverged commit -q --allow-empty -m local
  advance_origin
  git -C ws/b-current pull -q
  run pullr --jobs 8 ws
  [ "$status" -eq 1 ]
  expected="+ a-behind (main, 2 new commits)
= b-current (main)
x c-diverged (main)"
  [[ "$output" == "$expected"* ]]
  [[ "$output" == *"+ d-behind (main, 2 new commits)"* ]]
  [[ "$output" == *"Repos: 4  updated: 2  up to date: 1  skipped: 0  failed: 1"* ]]
  [[ "$output" == *"Failed: c-diverged"* ]]
}

@test "--jobs 1 runs sequentially with the same result" {
  clone a-behind; clone b-current
  advance_origin
  git -C ws/b-current pull -q
  run pullr -j 1 ws
  [ "$status" -eq 0 ]
  [[ "$output" == "+ a-behind (main, 2 new commits)
= b-current (main)
"* ]]
}

@test "--jobs rejects non-positive and non-numeric values" {
  run pullr --jobs 0 ws
  [ "$status" -eq 2 ]
  run pullr --jobs=x ws
  [ "$status" -eq 2 ]
  run pullr -j
  [ "$status" -eq 2 ]
}

@test "--dry-run predicts each pull without changing anything, exits 1 if one would fail" {
  clone behind; clone ahead; clone diverged; clone clean
  git -C ws/diverged commit -q --allow-empty -m local
  advance_origin
  git -C ws/ahead pull -q
  git -C ws/ahead commit -q --allow-empty -m local
  git -C ws/clean pull -q
  local before
  before="$(git -C ws/behind rev-parse HEAD)"
  run pullr --dry-run ws
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "Dry run: nothing will be pulled." ]]
  [[ "$output" == *"+ behind (main, 2 new commits)"* ]]
  [[ "$output" == *"= ahead (main)"* ]]
  [[ "$output" == *"x diverged (main)
    diverged from upstream (behind 2, ahead 1): cannot fast-forward"* ]]
  [[ "$output" == *"= clean (main)"* ]]
  [[ "$output" == *"Repos: 4  would update: 1  up to date: 2  skipped: 0  would fail: 1"* ]]
  [[ "$output" == *"Failed: diverged"* ]]
  [ "$(git -C ws/behind rev-parse HEAD)" = "$before" ]
}

@test "--dry-run skips detached HEAD and no upstream like a real run" {
  clone detached
  git -C ws/detached checkout -q --detach
  git init -q -b main ws/local
  run pullr -n ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"- detached (detached HEAD)"* ]]
  [[ "$output" == *"- local (main has no upstream)"* ]]
  [[ "$output" == *"skipped: 2"* ]]
}

@test "--dry-run reports a fetch failure and exits 1" {
  clone broken
  git -C ws/broken remote set-url origin "$BATS_TEST_TMPDIR/missing.git"
  run pullr --dry-run ws
  [ "$status" -eq 1 ]
  [[ "$output" == *"x broken (main)"* ]]
  [[ "$output" == *"Failed: broken"* ]]
}

@test "--rebase puts local commits on top of a diverged upstream" {
  clone diverged; clone behind
  git -C ws/diverged commit -q --allow-empty -m local
  advance_origin
  run pullr --rebase ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ behind (main, 2 new commits)"* ]]
  [[ "$output" == *"+ diverged (main, 2 new commits, 1 rebased)"* ]]
  [[ "$output" == *"updated: 2"* ]]
  [ "$(git -C ws/diverged rev-parse HEAD~1)" = "$(git -C origin.git rev-parse main)" ]
  [ "$(git -C ws/diverged log -1 --format=%s)" = "local" ]
}

@test "--rebase aborts a conflicting rebase and leaves the repository untouched" {
  clone conflict
  echo theirs >seed/file && git -C seed add file && git -C seed commit -q -m theirs && git -C seed push -q origin main
  echo ours >ws/conflict/file && git -C ws/conflict add file && git -C ws/conflict commit -q -m ours
  local before
  before="$(git -C ws/conflict rev-parse HEAD)"
  run pullr -r ws
  [ "$status" -eq 1 ]
  [[ "$output" == *"x conflict (main)"* ]]
  [[ "$output" == *"CONFLICT"* ]]
  [[ "$output" == *"Failed: conflict"* ]]
  [ "$(git -C ws/conflict rev-parse HEAD)" = "$before" ]
  [ "$(cat ws/conflict/file)" = "ours" ]
  ! git -C ws/conflict rev-parse --verify --quiet REBASE_HEAD
  [ -z "$(git -C ws/conflict status --porcelain)" ]
}

@test "--dry-run --rebase predicts a rebase instead of a failure" {
  clone diverged
  git -C ws/diverged commit -q --allow-empty -m local
  advance_origin
  run pullr --dry-run --rebase ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ diverged (main, 2 new commits, 1 to rebase)"* ]]
  [[ "$output" == *"would update: 1"* ]]
  [ "$(git -C ws/diverged log -1 --format=%s)" = "local" ]
}
