#!/usr/bin/env bash
# bootstrap.sh — configure a GitHub repo for warren autonomous auto-merge.
# Run from anywhere; pass your repo as owner/name. Requires `gh` authed
# with a token that has admin rights on the repo.
#
#   ./bootstrap.sh your-org/your-project
set -euo pipefail

REPO="${1:?usage: ./bootstrap.sh owner/repo}"

echo ">> Enabling auto-merge + branch auto-delete on $REPO"
gh api --method PATCH "repos/$REPO" \
  -f allow_auto_merge=true \
  -f delete_branch_on_merge=true

echo ">> Removing required-review branch protection on main (keeps CI check)"
# Safe: auto-merge.yml only enables merge for PRs authored by the repo
# owner. External PRs still require manual merge.
gh api --method DELETE \
  "repos/$REPO/branches/main/protection/required_pull_request_reviews" \
  2>/dev/null || echo "   (no required-review protection found — fine)"

echo ">> Setting the AUTO_MERGE_PAT secret"
echo "   Paste a PAT with contents:write + pull-requests:write."
echo "   (Use a DIFFERENT token than GITHUB_TOKEN so merge commits trigger"
echo "    downstream workflows — GitHub suppresses GITHUB_TOKEN-authored pushes.)"
gh secret set AUTO_MERGE_PAT --repo "$REPO"

cat <<'NEXT'

>> Done. Remaining manual steps:
   1. Commit the scaffold (.github/, .warren/, .canopy/, agents/, docs/,
      CLAUDE.md) and push to main.
   2. Make sure a required status check named "ci" (or your CI job name)
      is set on main so PRs must pass CI before auto-merge fires:
        gh api --method PUT repos/OWNER/REPO/branches/main/protection \
          -f 'required_status_checks[strict]=true' \
          -f 'required_status_checks[contexts][]=ci' \
          -f 'enforce_admins=false' \
          -f 'required_pull_request_reviews=' \
          -f 'restrictions='
      (Adjust the context name to your CI job.)
   3. Open a test PR from the repo-owner account and confirm: CI runs,
      auto-merge enables, PR merges on green, head branch is deleted.
NEXT
