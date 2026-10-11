#!/bin/bash
set -euo pipefail

# Tests for scripts/post-gist.sh. A fake `gh` on PATH records its arguments
# and GH_HOST and publishes the files to a local bare repository, so no
# network or credentials are needed.

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly POST_GIST="${SCRIPT_DIRECTORY}/../scripts/post-gist.sh"

WORK_DIRECTORY="$(mktemp -d)"
readonly WORK_DIRECTORY
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

readonly FAKE_BIN="${WORK_DIRECTORY}/bin"
readonly RECORD_FILE="${WORK_DIRECTORY}/record"
readonly REPORT_FILE="${WORK_DIRECTORY}/report.md"
readonly REMOTE_DIRECTORY="${WORK_DIRECTORY}/remote"
readonly REMOTE_GIST="${REMOTE_DIRECTORY}/abc123.git"
readonly IMAGE_FILE="${WORK_DIRECTORY}/images/chart.png"
readonly GIST_URL="https://gist.github.com/tester/abc123"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

install_fake_gh() {
  mkdir -p "$FAKE_BIN"
  cat >"${FAKE_BIN}/gh" <<FAKE_GH
#!/bin/bash
{
  echo "GH_HOST=\${GH_HOST:-}"
  echo "ARGS=\$*"
} >"${RECORD_FILE}"
seed_directory="${WORK_DIRECTORY}/seed"
rm -rf "\$seed_directory" "${REMOTE_GIST}"
mkdir -p "\$seed_directory"
shift 2
while [ \$# -gt 0 ]; do
  case "\$1" in
    -d) shift 2 ;;
    -*) shift ;;
    *) cp "\$1" "\$seed_directory/"; shift ;;
  esac
done
git init -q --bare "${REMOTE_GIST}"
git -C "\$seed_directory" init -q
git -C "\$seed_directory" add -A
git -C "\$seed_directory" -c user.name=t -c user.email=t@example.com commit -q -m seed
git -C "\$seed_directory" push -q "${REMOTE_GIST}" HEAD:refs/heads/main 2>/dev/null
git -C "${REMOTE_GIST}" symbolic-ref HEAD refs/heads/main
if [ -n "\${FAKE_GH_REJECT_PUSH:-}" ]; then
  printf '#!/bin/sh\nexit 1\n' >"${REMOTE_GIST}/hooks/pre-receive"
  chmod +x "${REMOTE_GIST}/hooks/pre-receive"
fi
echo "${GIST_URL}"
FAKE_GH
  chmod +x "${FAKE_BIN}/gh"
}

# Creates a repository whose origin is the given URL and prints its path.
make_repository_with_origin() {
  local origin_url="$1"
  local repository
  repository="$(mktemp -d "${WORK_DIRECTORY}/repo-XXXXXX")"
  git init -q "$repository"
  git -C "$repository" remote add origin "$origin_url"
  echo "$repository"
}

# Runs the script with the gist clone URL redirected to the local bare repo.
run_post_gist() {
  local repository="$1"
  shift
  (
    cd "$repository"
    export PATH="${FAKE_BIN}:${PATH}"
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="url.${REMOTE_GIST}.insteadOf"
    export GIT_CONFIG_VALUE_0="${GIST_URL}.git"
    "$POST_GIST" "$@"
  )
}

assert_record_contains() {
  local expected="$1"
  grep -qF -- "$expected" "$RECORD_FILE" \
    || fail "expected '${expected}' in record: $(cat "$RECORD_FILE")"
}

read_remote_file() {
  git -C "$REMOTE_GIST" show "main:$1"
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
  [ "$output" = "$GIST_URL" ] || fail "unexpected output: ${output}"
}

test_should_fail_when_file_is_missing() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  if run_post_gist "$repository" "${WORK_DIRECTORY}/missing.md" 2>/dev/null; then
    fail "expected non-zero exit for a missing file"
  fi
}

test_should_fail_when_file_has_unsupported_extension() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  echo "text" >"${WORK_DIRECTORY}/report.txt"
  if run_post_gist "$repository" "${WORK_DIRECTORY}/report.txt" 2>/dev/null; then
    fail "expected non-zero exit for a non-.md, non-image file"
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

test_should_upload_multiple_markdown_files() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  echo "# Report ja" >"${WORK_DIRECTORY}/report.ja.md"
  run_post_gist "$repository" "$REPORT_FILE" "${WORK_DIRECTORY}/report.ja.md" >/dev/null
  assert_record_contains "report.md"
  assert_record_contains "report.ja.md"
}

test_should_push_image_to_gist_repository() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  run_post_gist "$repository" "$REPORT_FILE" "$IMAGE_FILE" >/dev/null
  git -C "$REMOTE_GIST" cat-file -e main:chart.png \
    || fail "chart.png was not pushed to the gist repository"
}

test_should_not_pass_image_to_gist_create() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  run_post_gist "$repository" "$REPORT_FILE" "$IMAGE_FILE" >/dev/null
  if grep -q "chart.png" "$RECORD_FILE"; then
    fail "gh gist create must not receive binary files: $(cat "$RECORD_FILE")"
  fi
}

test_should_rewrite_markdown_image_link_to_raw_url() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  printf '# R\n\n![chart](images/chart.png)\n' >"${WORK_DIRECTORY}/with-image.md"
  run_post_gist "$repository" "${WORK_DIRECTORY}/with-image.md" "$IMAGE_FILE" >/dev/null
  read_remote_file with-image.md | grep -qF "![chart](${GIST_URL}/raw/chart.png)" \
    || fail "image link was not rewritten: $(read_remote_file with-image.md)"
}

test_should_rewrite_html_image_tag_to_raw_url() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  printf '<img src="./chart.png" width="300">\n' >"${WORK_DIRECTORY}/html-image.md"
  run_post_gist "$repository" "${WORK_DIRECTORY}/html-image.md" "$IMAGE_FILE" >/dev/null
  read_remote_file html-image.md | grep -qF "src=\"${GIST_URL}/raw/chart.png\"" \
    || fail "img tag was not rewritten: $(read_remote_file html-image.md)"
}

test_should_rewrite_image_links_in_every_markdown_file() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  printf '![c](chart.png)\n' >"${WORK_DIRECTORY}/doc.en.md"
  printf '![c](chart.png)\n' >"${WORK_DIRECTORY}/doc.ja.md"
  run_post_gist "$repository" "${WORK_DIRECTORY}/doc.en.md" \
    "${WORK_DIRECTORY}/doc.ja.md" "$IMAGE_FILE" >/dev/null
  read_remote_file doc.ja.md | grep -qF "${GIST_URL}/raw/chart.png" \
    || fail "second markdown file link was not rewritten"
}

test_should_leave_other_links_untouched() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  printf '![x](other.png) [t](chart.png.txt)\n' >"${WORK_DIRECTORY}/other.md"
  run_post_gist "$repository" "${WORK_DIRECTORY}/other.md" "$IMAGE_FILE" >/dev/null
  [ "$(read_remote_file other.md)" = '![x](other.png) [t](chart.png.txt)' ] \
    || fail "unrelated links changed: $(read_remote_file other.md)"
}

test_should_fail_when_image_file_is_missing() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  if run_post_gist "$repository" "$REPORT_FILE" "${WORK_DIRECTORY}/images/missing.png" 2>/dev/null; then
    fail "expected non-zero exit for a missing image"
  fi
}

test_should_fail_when_image_basenames_collide() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  mkdir -p "${WORK_DIRECTORY}/other"
  cp "$IMAGE_FILE" "${WORK_DIRECTORY}/other/chart.png"
  if run_post_gist "$repository" "$REPORT_FILE" "$IMAGE_FILE" "${WORK_DIRECTORY}/other/chart.png" 2>/dev/null; then
    fail "expected non-zero exit when two images share a basename"
  fi
}

test_should_fail_when_image_name_has_unsafe_characters() {
  local repository error_output
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  cp "$IMAGE_FILE" "${WORK_DIRECTORY}/images/bad name&.png"
  if error_output="$(run_post_gist "$repository" "$REPORT_FILE" "${WORK_DIRECTORY}/images/bad name&.png" 2>&1)"; then
    fail "expected non-zero exit for an unsafe image name"
  fi
  grep -qF "unsafe image file name" <<<"$error_output" \
    || fail "expected the unsafe-name message, got: ${error_output}"
}

test_should_accept_markdown_names_that_differ_only_in_directory_spacing() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  mkdir -p "${WORK_DIRECTORY}/a b" "${WORK_DIRECTORY}/x b"
  echo "# one" >"${WORK_DIRECTORY}/a b/one.md"
  echo "# two" >"${WORK_DIRECTORY}/x b/two.md"
  run_post_gist "$repository" "${WORK_DIRECTORY}/a b/one.md" "${WORK_DIRECTORY}/x b/two.md" >/dev/null \
    || fail "paths with spaces must not be reported as duplicates"
}

test_should_accept_markdown_name_with_single_quote() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  echo "# quoted" >"${WORK_DIRECTORY}/it's.md"
  run_post_gist "$repository" "${WORK_DIRECTORY}/it's.md" >/dev/null \
    || fail "a single quote in a Markdown name must not break the script"
}

test_should_report_gist_url_when_image_push_fails() {
  local repository error_output
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  if error_output="$(FAKE_GH_REJECT_PUSH=1 run_post_gist "$repository" "$REPORT_FILE" "$IMAGE_FILE" 2>&1)"; then
    fail "expected non-zero exit when the image push is rejected"
  fi
  grep -qF "$GIST_URL" <<<"$error_output" \
    || fail "the created gist URL was not reported: ${error_output}"
}

test_should_remove_temporary_directory_when_image_push_fails() {
  local repository temporary_root="${WORK_DIRECTORY}/tmp-root"
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  mkdir -p "$temporary_root"
  TMPDIR="$temporary_root" FAKE_GH_REJECT_PUSH=1 \
    run_post_gist "$repository" "$REPORT_FILE" "$IMAGE_FILE" >/dev/null 2>&1 || true
  [ -z "$(ls -A "$temporary_root")" ] \
    || fail "temporary directory leaked: $(ls "$temporary_root")"
}

test_should_fail_when_no_markdown_file_is_given() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  if run_post_gist "$repository" "$IMAGE_FILE" 2>/dev/null; then
    fail "expected non-zero exit with only an image"
  fi
}

test_should_rewrite_link_with_title() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  printf '![c](images/chart.png "p99 latency")\n' >"${WORK_DIRECTORY}/titled.md"
  run_post_gist "$repository" "${WORK_DIRECTORY}/titled.md" "$IMAGE_FILE" >/dev/null 2>&1
  [ "$(read_remote_file titled.md)" = "![c](${GIST_URL}/raw/chart.png \"p99 latency\")" ] \
    || fail "titled link was not rewritten: $(read_remote_file titled.md)"
}

test_should_rewrite_reference_style_definition() {
  local repository
  repository="$(make_repository_with_origin https://github.com/owner/repo)"
  printf '![c][latency]\n\n[latency]: images/chart.png\n' >"${WORK_DIRECTORY}/reference.md"
  run_post_gist "$repository" "${WORK_DIRECTORY}/reference.md" "$IMAGE_FILE" >/dev/null 2>&1
  read_remote_file reference.md | grep -qxF "[latency]: ${GIST_URL}/raw/chart.png" \
    || fail "reference definition was not rewritten: $(read_remote_file reference.md)"
}

test_should_fail_when_origin_url_has_no_host() {
  local repository
  repository="$(make_repository_with_origin /srv/git/repo.git)"
  if run_post_gist "$repository" "$REPORT_FILE" 2>/dev/null; then
    fail "expected non-zero exit for an origin URL without a host"
  fi
  [ ! -e "$RECORD_FILE" ] || fail "gh must not run: $(cat "$RECORD_FILE")"
}

main() {
  install_fake_gh
  echo "# Report" >"$REPORT_FILE"
  mkdir -p "$REMOTE_DIRECTORY" "$(dirname "$IMAGE_FILE")"
  printf '\211PNG\r\n\032\n' >"$IMAGE_FILE"
  local test_name
  for test_name in $(declare -F | awk '{print $3}' | grep '^test_'); do
    rm -f "$RECORD_FILE"
    "$test_name"
    echo "ok - ${test_name}"
  done
}

main "$@"
