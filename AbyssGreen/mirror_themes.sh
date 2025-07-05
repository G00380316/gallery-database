#!/bin/bash

json_file="hyde-themes.json"

# Check required tools
for cmd in git gh jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ '$cmd' is not installed."
        exit 1
    fi
done

# Get GitHub username
username=$(gh api user --jq .login)

# Build a list of all theme repo names from JSON
echo "🔍 Extracting theme names..."
theme_names=()
while IFS= read -r name; do
    theme_names+=("$name")
done < <(jq -r '.[].THEME' "$json_file" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

# 🗑️ Delete private repos created earlier by this script
echo "🧹 Cleaning up private repos from previous runs..."
gh repo list "$username" --json name,visibility --jq '.[] | select(.visibility=="PRIVATE") | .name' |
while read -r repo; do
    for theme in "${theme_names[@]}"; do
        if [[ "$repo" == "$theme" ]]; then
            echo "🗑️  Deleting private repo: $repo"
            gh repo delete "$repo" --yes
        fi
    done
done

# 📁 Prepare working directory
mkdir -p hyde-themes-clones
cd hyde-themes-clones || exit 1

# 🚀 Process each theme
jq -c '.[]' "../$json_file" | while read -r theme; do
    name=$(echo "$theme" | jq -r '.THEME' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

    if [ -d "$name" ]; then
        echo "⚠️  Skipping $name (already cloned)"
        continue
    fi

    clone_url=$(echo "$theme" | jq -r '.LINK')
    echo "📦 Processing: $name"

    # Clone the original repo
    git clone --depth=1 "$clone_url" "$name" || {
        echo "❌ Failed to clone $clone_url"
        continue
    }

    cd "$name" || continue

    # Create a public GitHub repo
    gh repo create "$name" --public --confirm || {
        echo "❌ Failed to create GitHub repo: $name"
        cd ..
        continue
    }

    # Push to the new GitHub repo (HTTPS)
    git remote remove origin
    git remote add origin "https://github.com/$username/$name.git"
    git push -u origin HEAD || echo "❌ Push failed for $name"

    cd ..
    echo "✅ Done with $name"
done

