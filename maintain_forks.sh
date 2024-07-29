#!/bin/bash

# The purpose of this script is to ensure all of our Github forks are kept up to date with their origins.

# GitHub username and personal access token
GITHUB_USERNAME=""
GITHUB_TOKEN=""
CLONE_DIR=
SSH_KEY_PATH=""

# Ensure SSH key is added to the SSH agent
ssh-add -l | grep "$SSH_KEY_PATH" > /dev/null || ssh-add "$SSH_KEY_PATH"

# Function to get the list of forked repositories
get_forks() {
    local url="https://api.github.com/users/0din-ai/repos?per_page=100"
    local repos=()

    while [ "$url" != "null" ]; do
        response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$url")
        forks=$(echo "$response" | jq -r '.[] | select(.fork == true) | .ssh_url')
        repos+=($forks)
        url=$(echo "$response" | jq -r 'if . | length == 100 then .[99].owner.repos_url + "?per_page=100&page=" + (. | length / 100 | tostring) else null end')
    done

    echo "${repos[@]}"
}

# Function to clone repositories
clone_forks() {
    local forks=("$@")
    mkdir -p "$CLONE_DIR"

    for repo in "${forks[@]}"; do
        repo_name=$(basename "$repo" .git)
        if [ ! -d "$CLONE_DIR/$repo_name" ]; then
            GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH" git clone "$repo" "$CLONE_DIR/$repo_name"
        else
            echo "$CLONE_DIR/$repo_name already exists, skipping clone."
        fi
    done
}

# Function to update repositories
update_forks() {
    local forks=("$@")
    local updated_repos=()

    for repo in "${forks[@]}"; do
        repo_name=$(basename "$repo" .git)
        repo_path="$CLONE_DIR/$repo_name"

        if [ -d "$repo_path/.git" ]; then
            cd "$repo_path"

            # Add upstream remote if not already added
            if ! git remote | grep -q upstream; then
                echo "Fetching parent repo information for $repo_name..."
                repo_full_name=$(echo "$repo" | sed 's|git@github.com:||; s|\.git$||')
                api_url="https://api.github.com/repos/${repo_full_name}"
                echo "API URL: $api_url"
                repo_info=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$api_url")
                echo "Repo info: $repo_info"
                parent_repo=$(echo "$repo_info" | jq -r '.parent.full_name')
                if [ "$parent_repo" == "null" ]; then
                    echo "Upstream repository for $repo_name not found, skipping."
                    continue
                fi
                upstream_url="git@github.com:${parent_repo}.git"
                echo "Adding upstream remote $upstream_url for $repo_name"
                GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH" git remote add upstream "$upstream_url"
            fi

            # Fetch latest changes from upstream
            echo "Fetching latest changes from upstream for $repo_name..."
            if ! GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH" git fetch upstream; then
                echo "Failed to fetch from upstream for $repo_name, skipping."
                continue
            fi

            # Checkout main/master branch
            echo "Checking out main/master branch for $repo_name..."
            if ! git checkout main; then
                if ! git checkout master; then
                    echo "Neither main nor master branch found for $repo_name, skipping."
                    continue
                fi
            fi

            # Merge upstream changes
            echo "Merging upstream changes for $repo_name..."
            if ! GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH" git merge upstream/main; then
                if ! GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH" git merge upstream/master; then
                    echo "Failed to merge from upstream for $repo_name, skipping."
                    continue
                fi
            fi

            # Push changes to your fork
            echo "Pushing changes to origin for $repo_name..."
            if ! GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH" git push origin main; then
                if ! GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH" git push origin master; then
                    echo "Failed to push updates for $repo_name, skipping."
                    continue
                fi
            fi

            echo "Updated $repo_path"
            updated_repos+=("$repo_name")
        else
            echo "$repo_path is not a valid git repository, skipping update."
        fi
    done

    echo "Repositories updated and synced:"
    for updated_repo in "${updated_repos[@]}"; do
        echo "$updated_repo"
    done
}

# Main script execution
forks=($(get_forks))
clone_forks "${forks[@]}"
update_forks "${forks[@]}"
