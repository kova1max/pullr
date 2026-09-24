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
  [[ "$output" == *"Repos: 4  updated: 2  up to date: 1  dirty: 0  skipped: 0  failed: 1"* ]]
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
  [[ "$output" == *"Repos: 4  would update: 1  up to date: 2  dirty: 0  skipped: 0  would fail: 1"* ]]
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

# Runs pullr with stdout on a pseudo-terminal, so its color decision sees a TTY.
pullr_tty() {
  python3 - "${PULLR_BASH:-bash}" "$PULLR" "$@" <<'PY'
import os, subprocess, sys
leader, follower = os.openpty()
proc = subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL, stdout=follower, stderr=follower)
os.close(follower)
out = b""
while True:
    try:
        chunk = os.read(leader, 4096)
    except OSError:  # Linux raises EIO once the child closes its side
        break
    if not chunk:
        break
    out += chunk
sys.stdout.write(out.decode().replace("\r\n", "\n"))
sys.exit(proc.wait())
PY
}

@test "colors output on a terminal" {
  clone repo
  run pullr_tty ws
  [[ "$output" == *$'\e[2m='* ]]
}

@test "NO_COLOR disables color on a terminal" {
  clone repo
  NO_COLOR=1 run pullr_tty ws
  [[ "$output" == *"= repo (main)"* ]]
  [[ "$output" != *$'\e['* ]]
}

@test "--no-color disables color on a terminal" {
  clone repo
  run pullr_tty --no-color ws
  [[ "$output" == *"= repo (main)"* ]]
  [[ "$output" != *$'\e['* ]]
}

@test "empty NO_COLOR keeps color, as the spec says" {
  clone repo
  NO_COLOR= run pullr_tty ws
  [[ "$output" == *$'\e[2m='* ]]
}

# Origin changes `file`; the clone has local edits to the same file.
make_blocked() {
  clone "$1"
  echo base >seed/file && git -C seed add file && git -C seed commit -q -m base && git -C seed push -q origin main
  git -C "ws/$1" pull -q
  echo upstream >seed/file && git -C seed commit -q -am upstream && git -C seed push -q origin main
  echo local >"ws/$1/file"
}

@test "--no-autostash: local changes that block a fast-forward are reported as dirty, not failed" {
  make_blocked blocked
  local before
  before="$(git -C ws/blocked rev-parse HEAD)"
  run pullr --no-autostash ws
  [ "$status" -eq 0 ]
  [[ "$output" == "~ blocked (main, 1 commit held back by local changes)"* ]]
  [[ "$output" != *"error:"* && "$output" != *"overwritten"* ]]
  [[ "$output" == *"dirty: 1"* && "$output" == *"Dirty: blocked"* ]]
  [ "$(git -C ws/blocked rev-parse HEAD)" = "$before" ]
  [ "$(cat ws/blocked/file)" = "local" ]
}

@test "local changes that do not touch incoming files still fast-forward" {
  clone edited
  echo scratch >ws/edited/notes.txt
  advance_origin
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ edited (main, 2 new commits)"* ]]
  [ "$(cat ws/edited/notes.txt)" = "scratch" ]
}

@test "--no-autostash: an untracked file in the way is reported as dirty" {
  clone untracked
  echo upstream >seed/new && git -C seed add new && git -C seed commit -q -m new && git -C seed push -q origin main
  echo mine >ws/untracked/new
  run pullr --no-autostash ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"~ untracked (main, 1 commit held back by local changes)"* ]]
  [ "$(cat ws/untracked/new)" = "mine" ]
}

@test "--no-autostash: --dry-run predicts dirty and a clean update the same way a real run does" {
  clone edited
  make_blocked blocked
  echo scratch >ws/edited/notes.txt
  run pullr --no-autostash --dry-run ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"~ blocked (main, 1 commit held back by local changes)"* ]]
  [[ "$output" == *"+ edited (main, 2 new commits)"* ]]
  [[ "$output" == *"dirty: 1"* ]]
  run pullr --no-autostash ws
  [[ "$output" == *"~ blocked (main, 1 commit held back by local changes)"* ]]
  [[ "$output" == *"+ edited (main, 2 new commits)"* ]]
}

@test "--no-autostash: --rebase on a diverged branch with local edits reports dirty and rebases nothing" {
  clone both
  echo base >seed/file && git -C seed add file && git -C seed commit -q -m base && git -C seed push -q origin main
  git -C ws/both pull -q
  git -C ws/both commit -q --allow-empty -m local
  advance_origin
  echo local >ws/both/file
  local before
  before="$(git -C ws/both rev-parse HEAD)"
  run pullr --no-autostash --rebase ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"~ both (main, 2 commits held back by local changes)"* ]]
  [ "$(git -C ws/both rev-parse HEAD)" = "$before" ]
  [ "$(cat ws/both/file)" = "local" ]
}

@test "runs 8 jobs at a time by default" {
  run pullr --help
  [[ "$output" == *"(default: 8)"* ]]
  grep -q '^jobs=8$' "$PULLR"
}

# app.git has submodule lib (from lib.git); ws/app is a recursive clone whose
# lib is on branch main. Local file remotes need protocol.file.allow.
make_app_with_submodule() {
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
  git init -q --bare -b main lib.git
  git clone -q lib.git libw 2>/dev/null
  git -C libw commit -q --allow-empty -m lib1 && git -C libw push -q origin main
  git init -q --bare -b main app.git
  git clone -q app.git appw 2>/dev/null
  git -C appw submodule add -q "$BATS_TEST_TMPDIR/lib.git" lib 2>/dev/null
  git -C appw commit -q -m "add lib" && git -C appw push -q origin main
  git clone -q --recurse-submodules app.git ws/app 2>/dev/null
  git -C ws/app/lib checkout -q main
}

advance_lib() {
  git -C libw commit -q --allow-empty -m "lib $1" && git -C libw push -q origin main
}

bump_app_pointer() {
  git -C appw/lib pull -q origin main 2>/dev/null
  git -C appw commit -q -am "bump lib" && git -C appw push -q origin main
}

@test "without --submodules, submodules are left alone" {
  make_app_with_submodule
  advance_lib 2
  local before
  before="$(git -C ws/app/lib rev-parse HEAD)"
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" != *"lib"* ]]
  [ "$(git -C ws/app/lib rev-parse HEAD)" = "$before" ]
}

@test "--submodules fast-forwards a submodule on its branch, indented under its parent" {
  make_app_with_submodule
  advance_lib 2
  run pullr --submodules ws
  [ "$status" -eq 0 ]
  [[ "$output" == "= app (main)
  + app/lib (main, 1 new commit)"* ]]
  [[ "$output" == *"Repos: 2  updated: 1  up to date: 1"* ]]
  [ "$(git -C ws/app/lib rev-parse HEAD)" = "$(git -C lib.git rev-parse main)" ]
  [ "$(git -C ws/app/lib branch --show-current)" = "main" ]
}

@test "--submodules skips a submodule on a detached HEAD" {
  make_app_with_submodule
  git -C ws/app/lib checkout -q --detach
  run pullr --submodules -j 1 ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"  - app/lib (detached HEAD)"* ]]
}

@test "--no-autostash: --submodules reports a dirty submodule by its full path" {
  make_app_with_submodule
  echo base >libw/file && git -C libw add file && git -C libw commit -q -m base && git -C libw push -q origin main
  git -C ws/app/lib pull -q
  echo upstream >libw/file && git -C libw commit -q -am upstream && git -C libw push -q origin main
  echo local >ws/app/lib/file
  run pullr --no-autostash --submodules ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"  ~ app/lib (main, 1 commit held back by local changes)"* ]]
  [[ "$output" == *"Dirty: app/lib"* ]]
}

@test "a submodule on its own branch does not make the parent look dirty" {
  make_app_with_submodule
  git -C ws/app/lib commit -q --allow-empty -m "my lib work"
  advance_lib 2
  bump_app_pointer
  run pullr --dry-run ws
  [[ "$output" == *"+ app (main, 1 new commit)"* ]]
  run pullr --rebase ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ app (main, 1 new commit)"* ]]
  [ "$(git -C ws/app/lib log -1 --format=%s)" = "my lib work" ]
}

@test "honours submodule.recurse like git pull does" {
  make_app_with_submodule
  git -C ws/app config submodule.recurse true
  advance_lib 2
  bump_app_pointer
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ app (main, 1 new commit)"* ]]
  [ "$(git -C ws/app/lib rev-parse HEAD)" = "$(git -C lib.git rev-parse main)" ]
}

# Origin changes line 2 of `file`; the clone edits `file` too.
make_edited() {
  clone "$1"
  printf 'a\nb\nc\n' >seed/file && git -C seed add file && git -C seed commit -q -m base && git -C seed push -q origin main
  git -C "ws/$1" pull -q
  printf 'a\nUPSTREAM\nc\n' >seed/file && git -C seed commit -q -am upstream && git -C seed push -q origin main
}

@test "autostash (default): local edits are stashed, the update is made and they are reapplied" {
  make_edited repo
  printf 'a\nb\nc\nmine\n' >ws/repo/file
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ repo (main, 1 new commit, local changes reapplied)"* ]]
  [ "$(git -C ws/repo rev-parse HEAD)" = "$(git -C origin.git rev-parse main)" ]
  [ "$(cat ws/repo/file)" = "$(printf 'a\nUPSTREAM\nc\nmine')" ]
  [ -z "$(git -C ws/repo stash list)" ]
}

@test "autostash: a conflict puts the repository back exactly as it was" {
  make_edited repo
  printf 'a\nMINE\nc\n' >ws/repo/file
  echo scratch >ws/repo/untracked.txt
  local before_head before_status
  before_head="$(git -C ws/repo rev-parse HEAD)"
  before_status="$(git -C ws/repo status --porcelain)"
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"~ repo (main, 1 commit held back because local changes conflict with them)"* ]]
  [[ "$output" == *"Dirty: repo"* ]]
  [ "$(git -C ws/repo rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C ws/repo status --porcelain)" = "$before_status" ]
  [ "$(cat ws/repo/file)" = "$(printf 'a\nMINE\nc')" ]
  [ "$(cat ws/repo/untracked.txt)" = "scratch" ]
  ! grep -q '<<<<<<<' ws/repo/file
  [ -z "$(git -C ws/repo stash list)" ]
}

@test "autostash: staged and unstaged changes keep their state" {
  make_edited repo
  echo staged >ws/repo/new.txt && git -C ws/repo add new.txt
  printf 'a\nb\nc\nmine\n' >ws/repo/file
  run pullr ws
  [[ "$output" == *"local changes reapplied"* ]]
  [ "$(git -C ws/repo diff --cached --name-only)" = "new.txt" ]
  [ "$(git -C ws/repo diff --name-only)" = "file" ]
}

@test "autostash: an untracked file that collides with an incoming one rolls back" {
  clone repo
  echo upstream >seed/new && git -C seed add new && git -C seed commit -q -m new && git -C seed push -q origin main
  echo mine >ws/repo/new
  local before
  before="$(git -C ws/repo rev-parse HEAD)"
  run pullr ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"~ repo (main, 1 commit held back because local changes conflict with them)"* ]]
  [ "$(git -C ws/repo rev-parse HEAD)" = "$before" ]
  [ "$(cat ws/repo/new)" = "mine" ]
  [ "$(git -C ws/repo status --porcelain)" = "?? new" ]
  [ -z "$(git -C ws/repo stash list)" ]
}

@test "autostash leaves the user's own stash entries alone" {
  make_edited repo
  echo keep >ws/repo/other && git -C ws/repo stash push -q --include-untracked -m "users own"
  printf 'a\nb\nc\nmine\n' >ws/repo/file
  run pullr ws
  [[ "$output" == *"local changes reapplied"* ]]
  [ "$(git -C ws/repo stash list --format=%s)" = "On main: users own" ]
}

@test "autostash with --rebase: rebases local commits and reapplies local edits" {
  make_edited repo
  git -C ws/repo commit -q --allow-empty -m "local commit"
  git -C seed commit -q --allow-empty -m more && git -C seed push -q origin main
  printf 'a\nb\nc\nmine\n' >ws/repo/file
  run pullr --rebase ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ repo (main, 2 new commits, 1 rebased, local changes reapplied)"* ]]
  [ "$(git -C ws/repo log -1 --format=%s)" = "local commit" ]
  [ "$(cat ws/repo/file)" = "$(printf 'a\nUPSTREAM\nc\nmine')" ]
}

@test "--dry-run shows which updates would autostash" {
  make_edited repo
  printf 'a\nMINE\nc\n' >ws/repo/file
  run pullr --dry-run ws
  [[ "$output" == *"+ repo (main, 1 new commit, local changes to autostash)"* ]]
  [ "$(cat ws/repo/file)" = "$(printf 'a\nMINE\nc')" ]
}

@test "-s is short for --submodules" {
  make_app_with_submodule
  advance_lib 2
  run pullr -s ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"  + app/lib (main, 1 new commit)"* ]]
}

@test "short options combine: -sn, -j8, -snj 1 and -rs" {
  make_app_with_submodule
  git -C ws/app/lib commit -q --allow-empty -m "my lib work"
  advance_lib 2
  run pullr -sn ws
  [[ "$output" == "Dry run: nothing will be pulled."* ]]
  [[ "$output" == *"  x app/lib (main)"* ]]
  run pullr -j8 -n ws
  [ "$status" -eq 0 ]
  run pullr -snj 1 ws
  [[ "$output" == *"  x app/lib (main)"* ]]
  run pullr -rs ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"  + app/lib (main, 1 new commit, 1 rebased)"* ]]
  [ "$(git -C ws/app/lib log -1 --format=%s)" = "my lib work" ]
}

@test "an unknown letter in a bundle is rejected" {
  run pullr -rx ws
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option: -x"* ]]
  run pullr -rj
  [ "$status" -eq 2 ]
}
