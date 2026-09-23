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
  [[ "$output" == *"+ behind (main, 2 new commit(s))"* ]]
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
  [[ "$output" == *"+ other (main, 2 new commit(s))"* ]]
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
