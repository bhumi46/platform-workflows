#!/usr/bin/env bats
# SemVer 2.0.0 precedence examples (section 11 of the spec) plus our dev/rc lifecycle.

cmp() { "$BATS_TEST_DIRNAME/../scripts/semver-compare" "$1" "$2"; }

@test "core versions compare numerically" {
  [ "$(cmp 1.0.0 2.0.0)" = -1 ]
  [ "$(cmp 2.1.0 2.0.9)" = 1 ]
  [ "$(cmp 0.10.0 0.9.0)" = 1 ]
  [ "$(cmp 1.2.3 1.2.3)" = 0 ]
}

@test "lifecycle order: dev < rc < final < next patch" {
  [ "$(cmp 0.2.0-dev.9 0.2.0-dev.10)" = -1 ]
  [ "$(cmp 0.2.0-dev.10 0.2.0-rc.1)" = -1 ]
  [ "$(cmp 0.2.0-rc.3 0.2.0)" = -1 ]
  [ "$(cmp 0.2.0 0.2.0-rc.3)" = 1 ]
  [ "$(cmp 0.2.0 0.2.1-dev.1)" = -1 ]
}

@test "spec example chain" {
  chain=(1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0)
  for ((i = 0; i < ${#chain[@]} - 1; i++)); do
    [ "$(cmp "${chain[$i]}" "${chain[$((i + 1))]}")" = -1 ]
  done
}

@test "build metadata is ignored" {
  [ "$(cmp 1.0.0+abc 1.0.0+def)" = 0 ]
}

@test "invalid versions are rejected" {
  run cmp 1.0 1.0.0
  [ "$status" -eq 2 ]
  run cmp 80c52986f80d0e3979c44b37fae42c2d2e369a64 1.0.0
  [ "$status" -eq 2 ]
}
