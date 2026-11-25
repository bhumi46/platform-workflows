#!/usr/bin/env bats
# Each test builds a throwaway git repo and checks one versioning rule of scripts/semver-next.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/semver-next"
  cd "$BATS_TEST_TMPDIR"
  git init -q -b main repo && cd repo
  git config user.email t@example.com && git config user.name t
  git config commit.gpgsign false
  mkdir -p src charts/svc
}

# commit <path> <message...>
commit() {
  local path=$1; shift
  echo "$RANDOM$RANDOM" >> "$path"
  git add -A && git commit -q -m "$@"
}

# v <args...>  -> prints only the version
v() { "$SCRIPT" "$@" | sed -n 's/^version=//p'; }
kv() { "$SCRIPT" "${@:2}" | sed -n "s/^$1=//p"; }

@test "first release of a new project is 0.1.0" {
  commit src/a "feat: first"
  [ "$(v --stage final)" = "0.1.0" ]
  [ "$(v --stage dev)" = "0.1.0-dev.1" ]
}

@test "fix -> patch, feat -> minor" {
  commit src/a "feat: start" && git tag v0.1.0
  commit src/a "fix: bug"
  [ "$(v --stage final)" = "0.1.1" ]
  commit src/a "feat: new api"
  [ "$(v --stage final)" = "0.2.0" ]
  [ "$(v --stage dev)" = "0.2.0-dev.2" ]
}

@test "breaking change bumps minor while 0.x, major from 1.0.0" {
  commit src/a "feat: start" && git tag v0.4.2
  commit src/a "feat!: drop v1 endpoints"
  [ "$(v --stage final)" = "0.5.0" ]
  git tag v1.0.0
  commit src/a "refactor: x" -m "BREAKING CHANGE: config format changed"
  [ "$(v --stage final)" = "2.0.0" ]
}

@test "scoped types and perf are recognised" {
  commit src/a "feat: start" && git tag v1.2.3
  commit src/a "perf(db): faster query"
  [ "$(v --stage final)" = "1.2.4" ]
  commit src/a "feat(api)!: rename field"
  [ "$(v --stage final)" = "2.0.0" ]
}

@test "chore-only changes still give a patch pre-release" {
  commit src/a "feat: start" && git tag v0.1.0
  commit src/a "chore: deps"
  [ "$(v --stage dev)" = "0.1.1-dev.1" ]
  [ "$(kv bump --stage dev)" = "none" ]
}

@test "Release-As forces a version (GA 1.0.0)" {
  commit src/a "feat: start" && git tag v0.9.0
  commit src/a "feat: ready" -m "Release-As: 1.0.0"
  [ "$(v --stage final)" = "1.0.0" ]
  [ "$(v --stage rc)" = "1.0.0-rc.1" ]
}

@test "no changes on the path since the tag reuses the tag version" {
  commit src/a "feat: start" && git tag v0.3.0
  [ "$(v --stage dev)" = "0.3.0" ]
  [ "$(kv changed --stage dev)" = "false" ]
}

@test "app ignores chart commits, chart ignores app commits" {
  commit src/a "feat: app" && git tag v0.1.0 && git tag chart-v0.1.0
  commit charts/svc/a "feat: new probe"
  commit charts/svc/a "fix: probe path"
  # app: nothing changed outside charts/
  [ "$(v --prefix v --exclude charts/ --stage dev)" = "0.1.0" ]
  [ "$(kv changed --prefix v --exclude charts/ --stage dev)" = "false" ]
  # chart: 2 chart commits, a feat -> minor
  [ "$(v --prefix chart-v --include charts/svc --stage dev)" = "0.2.0-dev.2" ]
  commit src/a "fix: app bug"
  [ "$(v --prefix v --exclude charts/ --stage dev)" = "0.1.1-dev.1" ]
  [ "$(v --prefix chart-v --include charts/svc --stage dev)" = "0.2.0-dev.2" ]
}

@test "pre-release tags are ignored as base" {
  commit src/a "feat: start" && git tag v0.2.0 && git tag v0.3.0-rc.1
  commit src/a "fix: x"
  [ "$(kv last_tag --stage final)" = "v0.2.0" ]
  [ "$(v --stage final)" = "0.2.1" ]
}

@test "highest tag wins (0.10.0 > 0.9.0)" {
  commit src/a "feat: a" && git tag v0.9.0
  commit src/a "feat: b" && git tag v0.10.0
  commit src/a "fix: c"
  [ "$(v --stage final)" = "0.10.1" ]
}

@test "release candidate numbering counts from the branch point" {
  commit src/a "feat: start" && git tag v0.1.0
  git checkout -q -b develop
  commit src/a "feat: one"
  commit src/a "feat: two"
  git checkout -q -b release/0.2
  [ "$(v --stage rc --since develop)" = "0.2.0-rc.1" ]
  commit src/a "fix: found in qa"
  [ "$(v --stage rc --since develop)" = "0.2.0-rc.2" ]
  [ "$(v --stage final)" = "0.2.0" ]
}

@test "GitFlow: after release + back-merge, develop counts from the new tag" {
  commit src/a "feat: start" && git tag v0.1.0
  git checkout -q -b develop
  commit src/a "feat: one"
  git checkout -q -b release/0.2
  commit src/b "fix: qa"
  git checkout -q main && git merge -q --no-ff release/0.2 -m "Merge release/0.2"
  git tag v0.2.0 release/0.2
  git checkout -q develop
  commit src/c "feat: for 0.3"
  git merge -q --no-ff main -m "Merge main into develop"
  [ "$(kv last_tag --stage dev)" = "v0.2.0" ]
  [ "$(v --stage dev)" = "0.3.0-dev.1" ]
}

@test "hotfix from main gives a patch rc (rc.1 = state at branch creation)" {
  commit src/a "feat: start" && git tag v0.2.0
  git checkout -q -b hotfix/0.2.1
  # nothing changed yet: the released version is reused, no new artifact
  [ "$(v --stage rc --since main)" = "0.2.0" ]
  commit src/a "fix: urgent"
  [ "$(v --stage rc --since main)" = "0.2.1-rc.2" ]
  [ "$(v --stage final)" = "0.2.1" ]
}

@test "rejects a bad stage" {
  run "$SCRIPT" --stage beta
  [ "$status" -eq 2 ]
}
