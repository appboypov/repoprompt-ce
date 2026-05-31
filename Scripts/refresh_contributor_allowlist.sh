#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAIMS_PROCESSOR_DIR="${CLAIMS_PROCESSOR_DIR:-"$(dirname "$ROOT")/ShutdownClaimProcessor"}"
CLAIMS_D1_DATABASE="${CLAIMS_D1_DATABASE:-repoprompt-claims}"
OUTPUT="${CONTRIBUTOR_ALLOWLIST_OUTPUT:-"$ROOT/.github/APPROVED_CONTRIBUTORS"}"
UNRESOLVED_OUTPUT="${CONTRIBUTOR_ALLOWLIST_UNRESOLVED_OUTPUT:-/tmp/repoprompt-ce-unresolved-github-ids.txt}"
SUMMARY_OUTPUT="${CONTRIBUTOR_ALLOWLIST_SUMMARY_OUTPUT:-/tmp/repoprompt-ce-access-list-summary.json}"
CONCURRENCY="${CONTRIBUTOR_ALLOWLIST_CONCURRENCY:-12}"

for command in gh jq npx sed sort uniq xargs; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'ERROR: required command is missing: %s\n' "$command" >&2
    exit 1
  fi
done

if [[ ! -f "$CLAIMS_PROCESSOR_DIR/wrangler.toml" ]]; then
  printf 'ERROR: claims processor Wrangler config not found: %s\n' "$CLAIMS_PROCESSOR_DIR/wrangler.toml" >&2
  exit 1
fi

tmp_dir="$(mktemp -d /tmp/repoprompt-ce-claims.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT
empty_env="$tmp_dir/empty-wrangler.env"
touch "$empty_env"

query="
SELECT
  MIN(TRIM(claims.github_username)) AS requested_login,
  COUNT(*) AS claim_rows
FROM claims
JOIN customers USING (email_hash)
WHERE customers.github_access_eligible = 1
  AND claims.github_username IS NOT NULL
  AND TRIM(claims.github_username) != ''
GROUP BY LOWER(TRIM(claims.github_username))
ORDER BY LOWER(TRIM(claims.github_username));
"

(
  cd "$CLAIMS_PROCESSOR_DIR"
  npx --yes wrangler d1 execute "$CLAIMS_D1_DATABASE" \
    --remote \
    --command "$query" \
    --env-file "$empty_env" \
    --json
) > "$tmp_dir/d1-output.txt"

# Wrangler may print a tool-install hint before its JSON payload.
sed -n '/^\[/,$p' "$tmp_dir/d1-output.txt" > "$tmp_dir/d1-results.json"
jq -e '.[0].success == true' "$tmp_dir/d1-results.json" >/dev/null
jq -r '.[0].results[].requested_login' "$tmp_dir/d1-results.json" > "$tmp_dir/requested-logins.txt"

xargs -P "$CONCURRENCY" -n 1 bash -c '
  requested="$1"
  payload="$(mktemp)"
  trap '\''rm -f "$payload"'\'' EXIT

  if gh api "users/$requested" > "$payload" 2>/dev/null; then
    resolved_login="$(jq -r .login "$payload")"
    resolved_type="$(jq -r .type "$payload")"
    if [[ "$resolved_type" == "User" ]]; then
      jq -nc \
        --arg requested "$requested" \
        --arg login "$resolved_login" \
        '\''{requested:$requested,resolvedLogin:$login,resolvedType:"User",reason:null}'\''
    else
      jq -nc \
        --arg requested "$requested" \
        --arg login "$resolved_login" \
        --arg type "$resolved_type" \
        '\''{requested:$requested,resolvedLogin:$login,resolvedType:$type,reason:"not_user"}'\''
    fi
  else
    jq -nc \
      --arg requested "$requested" \
      '\''{requested:$requested,resolvedLogin:null,resolvedType:null,reason:"not_found"}'\''
  fi
' _ < "$tmp_dir/requested-logins.txt" > "$tmp_dir/resolutions.jsonl"

jq -r 'select(.resolvedType == "User") | .resolvedLogin' "$tmp_dir/resolutions.jsonl" \
  | LC_ALL=C sort -f \
  | uniq -i \
  > "$tmp_dir/valid-users.txt"
jq -c 'select(.resolvedType != "User")' "$tmp_dir/resolutions.jsonl" \
  | LC_ALL=C sort \
  > "$UNRESOLVED_OUTPUT"

{
  printf '%s\n' \
    '# GitHub handles approved to bypass contribution auto-close' \
    '# Initial import: matched RepoPrompt customer claim-form submissions' \
    '# Refresh: ./Scripts/refresh_contributor_allowlist.sh' \
    '# Format: <username> <capability>' \
    '# capability:' \
    '#   issue  issues stay open' \
    '#   pr     issues and PRs stay open' \
    ''
  sed 's/$/ pr/' "$tmp_dir/valid-users.txt"
} > "$tmp_dir/APPROVED_CONTRIBUTORS"
mv "$tmp_dir/APPROVED_CONTRIBUTORS" "$OUTPUT"

matched_claim_rows="$(jq '.[0].results | map(.claim_rows) | add // 0' "$tmp_dir/d1-results.json")"
distinct_claim_ids="$(wc -l < "$tmp_dir/requested-logins.txt" | tr -d ' ')"
valid_github_users="$(wc -l < "$tmp_dir/valid-users.txt" | tr -d ' ')"
unresolved_ids="$(wc -l < "$UNRESOLVED_OUTPUT" | tr -d ' ')"

jq -n \
  --argjson matched_claim_rows "$matched_claim_rows" \
  --argjson distinct_claim_ids "$distinct_claim_ids" \
  --argjson valid_github_users "$valid_github_users" \
  --argjson unresolved_ids "$unresolved_ids" \
  '{
    matched_claim_rows: $matched_claim_rows,
    distinct_claim_ids: $distinct_claim_ids,
    valid_github_users: $valid_github_users,
    unresolved_ids: $unresolved_ids
  }' > "$SUMMARY_OUTPUT"

printf 'Updated %s with %s GitHub users.\n' "$OUTPUT" "$valid_github_users"
printf 'Summary: %s\n' "$SUMMARY_OUTPUT"
if [[ "$unresolved_ids" -ne 0 ]]; then
  printf 'WARNING: %s unresolved claim-form GitHub IDs remain: %s\n' \
    "$unresolved_ids" "$UNRESOLVED_OUTPUT" >&2
fi
