#!/usr/bin/env bash
set -euo pipefail

# ── Resolve platform ────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}-${ARCH}" in
  Linux-x86_64)   ARCHIVE="linux-amd64" ;;
  Linux-aarch64)  ARCHIVE="linux-arm64" ;;
  Darwin-arm64)   ARCHIVE="darwin-arm64" ;;
  *)
    echo "::error::Unsupported platform: ${OS}-${ARCH}. Skilldo provides binaries for linux-amd64, linux-arm64, and darwin-arm64."
    exit 1
    ;;
esac

# ── Resolve version ─────────────────────────────────────────────────
VERSION="${INPUT_VERSION}"
if [ "${VERSION}" = "latest" ]; then
  VERSION=$(curl -fsSL \
    -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/SkillDoAI/skilldo/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')

  if [ -z "${VERSION}" ]; then
    echo "::error::Failed to resolve latest skilldo version from GitHub Releases."
    exit 1
  fi
  echo "Resolved latest version: ${VERSION}"
fi

# ── Download and install binary ──────────────────────────────────────
TARBALL="skilldo-${VERSION}-${ARCHIVE}.tar.gz"
URL="https://github.com/SkillDoAI/skilldo/releases/download/${VERSION}/${TARBALL}"

echo "Downloading ${URL}"
TMPDIR="$(mktemp -d)"
curl -fsSL "${URL}" -o "${TMPDIR}/${TARBALL}"
tar xzf "${TMPDIR}/${TARBALL}" -C "${TMPDIR}"
chmod +x "${TMPDIR}/skilldo"

SKILLDO="${TMPDIR}/skilldo"
echo "Installed skilldo ${VERSION} (${ARCHIVE})"

# ── Resolve paths ────────────────────────────────────────────────────
TARGET_PATH="${INPUT_PATH}"
CONFIG_PATH="${TARGET_PATH}/${INPUT_CONFIG}"
OUTPUT_PATH="${TARGET_PATH}/${INPUT_OUTPUT}"

# Normalize ./
CONFIG_PATH="${CONFIG_PATH#./}"
OUTPUT_PATH="${OUTPUT_PATH#./}"
[ "${TARGET_PATH}" = "." ] && TARGET_PATH=""

# ── Run skilldo generate ─────────────────────────────────────────────
GENERATE_ARGS=("${INPUT_PATH}")
GENERATE_ARGS+=("--config" "${CONFIG_PATH}")
GENERATE_ARGS+=("--output" "${OUTPUT_PATH}")

if [ -n "${INPUT_LANGUAGE:-}" ]; then
  GENERATE_ARGS+=("--language" "${INPUT_LANGUAGE}")
fi

# Update mode: use existing SKILL.md as input reference
if [ "${INPUT_GENERATE_MODE:-update}" = "update" ] && [ -f "${OUTPUT_PATH}" ]; then
  GENERATE_ARGS+=("--input" "${OUTPUT_PATH}")
  echo "Update mode: using existing ${OUTPUT_PATH} as input reference"
fi

echo "Running: skilldo generate ${GENERATE_ARGS[*]}"
"${SKILLDO}" generate "${GENERATE_ARGS[@]}"

# ── Check for changes ────────────────────────────────────────────────
if git diff --quiet -- "${OUTPUT_PATH}" && ! git ls-files --others --exclude-standard -- "${OUTPUT_PATH}" | grep -q .; then
  echo "No changes to ${OUTPUT_PATH}"
  echo "changed=false" >> "${GITHUB_OUTPUT}"
  echo "pr-url=" >> "${GITHUB_OUTPUT}"
  exit 0
fi

echo "changed=true" >> "${GITHUB_OUTPUT}"
echo "Changes detected in ${OUTPUT_PATH}"

# ── Configure git ────────────────────────────────────────────────────
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# ── Commit and push/PR ──────────────────────────────────────────────
if [ "${INPUT_MODE}" = "commit" ]; then
  # Direct commit to current branch
  git add "${OUTPUT_PATH}"
  git commit -m "${INPUT_PR_TITLE}"
  git push
  echo "pr-url=" >> "${GITHUB_OUTPUT}"
  echo "Committed ${OUTPUT_PATH} to current branch"

elif [ "${INPUT_MODE}" = "pr" ]; then
  # Create branch, commit, open PR
  BRANCH="${INPUT_PR_BRANCH}"
  DEFAULT_BRANCH="$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')"

  # Delete remote branch if it exists (stale from previous run)
  git push origin --delete "${BRANCH}" 2>/dev/null || true

  git checkout -b "${BRANCH}"
  git add "${OUTPUT_PATH}"
  git commit -m "${INPUT_PR_TITLE}"
  git push -u origin "${BRANCH}"

  # Open PR
  export GH_TOKEN="${INPUT_GITHUB_TOKEN}"
  PR_URL=$(gh pr create \
    --title "${INPUT_PR_TITLE}" \
    --body "Automated SKILL.md update by [skilldo-action](https://github.com/SkillDoAI/skilldo-action)." \
    --base "${DEFAULT_BRANCH}" \
    --head "${BRANCH}" \
    2>&1) || true

  # If PR already exists, get its URL
  if echo "${PR_URL}" | grep -q "already exists"; then
    PR_URL=$(gh pr view "${BRANCH}" --json url -q .url 2>/dev/null || echo "")
  fi

  echo "pr-url=${PR_URL}" >> "${GITHUB_OUTPUT}"
  echo "PR: ${PR_URL}"

else
  echo "::error::Invalid mode '${INPUT_MODE}'. Use 'pr' or 'commit'."
  exit 1
fi

# ── Cleanup ──────────────────────────────────────────────────────────
rm -rf "${TMPDIR}"
