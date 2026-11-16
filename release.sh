#!/bin/bash
set -euo pipefail

BASE_BRANCH="main"
SOURCE_BRANCH="develop"
ORIGINAL_BRANCH=$(git symbolic-ref --short HEAD)
REPO_URL=$(git config --get remote.origin.url)

if [[ "$REPO_URL" =~ scm\.maze\.trading[:/](.+/.+?)(\.git)?$ ]]; then
  REPO="${BASH_REMATCH[1]}"
else
  REPO="$(basename "$REPO_URL" .git)"
fi

echo "📦 Repository: $REPO"
git fetch origin
git checkout "$SOURCE_BRANCH"
git reset --hard "origin/$SOURCE_BRANCH"
git checkout "$BASE_BRANCH"
git reset --hard "origin/$BASE_BRANCH"

if git merge-base --is-ancestor "origin/$SOURCE_BRANCH" "$BASE_BRANCH"; then
  echo "✅ $BASE_BRANCH is already up-to-date with $SOURCE_BRANCH"
else
  git merge --ff-only "origin/$SOURCE_BRANCH"
  git push origin "$BASE_BRANCH"
  echo "✅ Successfully fast-forwarded $BASE_BRANCH from $SOURCE_BRANCH"
fi

git checkout "$ORIGINAL_BRANCH"
