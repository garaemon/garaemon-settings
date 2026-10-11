#!/bin/bash
set -euo pipefail

# Tests for scripts/post-gist.sh. A fake `gh` on PATH records its arguments
# and GH_HOST, so no network or credentials are needed.

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly POST_GIST="${SCRIPT_DIRECTORY}/../scripts/post-gist.sh"

WORK_DIRECTORY="$(mktemp -d)"
readonly WORK_DIRECTORY
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

readonly FAKE_BIN="${WORK_DIRECTORY}/bin"
readonly RECORD_FILE="${WORK_DIRECTORY}/record"
readonly REPORT_FILE="${WORK_DIRECTORY}/report.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

install_fake_gh() {
  mkdir -p "$FAKE_BIN"
  cat >"${FAKE_BIN}/gh" <<EOF
#!/bin/bash
{
  echo "GH_HOST=\${GH_HOST:-}"
  echo "ARGS=\$*"
} >"${RECORD_FILE}"
echo "https://\${GH_HOST:-github.com}/gist/abc123"
EOF
  chmod +x "${FAKE_BIN}/gh"
}

# Creates a repository whose origin is the given URL and prints its path.
make_repository_with_origin() {
  local origin_url="$1"
  local repository="${WORK_DIRECTORY}/repo-$RANDOM"
  git init -q "$repository"
  git -C "$repository" remote add origin "$origin_url"
  echo "$repository"
}

run_post_gist() {
  local repository="$1"
  shift
  (cd "$repository" && PATH="${FAKE_BIN}:${PATH}" "$POST_GIST" "$@")
}

assert_record_contains() {
  local expected="$1"
  grep -qxF -- "$expected" "$RECORD_FILE" \
    || grep -qF -- "$expected" "$RECORD_FILE" \
    || fail "expected '${expected}' in record: $(cat "$RECORD_FILE")"
}

test_should_use_host_from_https_remote() {
  local repository
  repository="$(make_repository_with_origin https://ghe.example.com/owner/repo.git)"
  run_post_gist "$repository" "$REPORT_FILE" >/dev/null
  assert_record_contains "GH_HOST=ghe.example.com"
}

test_should_use_host_from_scp_like_remote() {
  local repository
  repository="$(make_repository_with_origin git@ghe.example.com:owner/repo.git)"
  run_post_gist "$repository" "$REPORT_FILE" >/dev/null
  assert_record_contains "GH_HOST=ghe.example.com"
}

test_should_use_host_from_ssh_url_with_port() {
  local repository
  repository="$(make_repository_with_origin ssh://git@ghe.example.com:2222/owner/repo.git)"
  run_post_gist "$repository" "$REPORT_FILE" >/dev/null
  assert_record_contains "GH_HOST=ghe.example.com"
}

test_should_override_inherited_gh_host() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  GH_HOST=stale.example.com run_post_gist "$repository" "$REPORT_FILE" >/dev/null
  assert_record_contains "GH_HOST=github.com"
}

test_should_create_secret_gist_by_default() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  run_post_gist "$repository" "$REPORT_FILE" >/dev/null
  if grep -q -- "--public" "$RECORD_FILE"; then
    fail "default gist must be secret: $(cat "$RECORD_FILE")"
  fi
}

test_should_create_public_gist_when_requested() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  run_post_gist "$repository" --public "$REPORT_FILE" >/dev/null
  assert_record_contains "--public"
}

test_should_pass_description() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  run_post_gist "$repository" --description "Weekly report" "$REPORT_FILE" >/dev/null
  assert_record_contains "-d Weekly report"
}

test_should_print_gist_url() {
  local repository output
  repository="$(make_repository_with_origin https://ghe.example.com/owner/repo)"
  output="$(run_post_gist "$repository" "$REPORT_FILE")"
  [ "$output" = "https://ghe.example.com/gist/abc123" ] \
    || fail "unexpected output: ${output}"
}

test_should_fail_when_file_is_missing() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  if run_post_gist "$repository" "${WORK_DIRECTORY}/missing.md" 2>/dev/null; then
    fail "expected non-zero exit for a missing file"
  fi
}

test_should_fail_when_file_is_not_markdown() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  echo "text" >"${WORK_DIRECTORY}/report.txt"
  if run_post_gist "$repository" "${WORK_DIRECTORY}/report.txt" 2>/dev/null; then
    fail "expected non-zero exit for a non-.md file"
  fi
}

test_should_fail_without_origin_remote() {
  local repository="${WORK_DIRECTORY}/no-origin"
  git init -q "$repository"
  if run_post_gist "$repository" "$REPORT_FILE" 2>/dev/null; then
    fail "expected non-zero exit without an origin remote"
  fi
}

test_should_fail_without_arguments() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  if run_post_gist "$repository" 2>/dev/null; then
    fail "expected non-zero exit without a file argument"
  fi
}

main() {
  install_fake_gh
  echo "# Report" >"$REPORT_FILE"
  local test_name
  for test_name in $(declare -F | awk '{print $3}' | grep '^test_'); do
    rm -f "$RECORD_FILE"
    "$test_name"
    echo "ok - ${test_name}"
  done
}

main "$@"
