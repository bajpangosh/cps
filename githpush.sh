#!/bin/bash

# Prompt for commit message
read -p "Enter commit message: " commitMessage

# Add all changes
git add .

# Commit with the message
git commit -m "$commitMessage"

# Push to the current branch
git push

echo "✅ Changes pushed to GitHub successfully."
