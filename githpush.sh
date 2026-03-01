#!/bin/bash

commitMessage="${1:-}"
if [[ -z "$commitMessage" ]]; then
    read -r -p "Enter commit message: " commitMessage
fi

if [[ -z "${commitMessage// }" ]]; then
    echo "Error: commit message cannot be empty."
    exit 1
fi

if ! status_output=$(git status --porcelain 2>/dev/null); then
    echo "Error: unable to run git status. Check your Git setup and try again."
    exit 1
fi

if [[ -z "$status_output" ]]; then
    echo "No changes detected. Nothing to commit."
    exit 0
fi

git add .

if git diff --cached --quiet; then
    echo "Nothing staged after git add. Exiting."
    exit 0
fi

if ! git commit -m "$commitMessage"; then
    echo "Commit failed. Resolve errors and retry."
    exit 1
fi

if ! git push; then
    echo "Push failed. Check remote/branch and retry."
    exit 1
fi

echo "Changes committed and pushed successfully."
