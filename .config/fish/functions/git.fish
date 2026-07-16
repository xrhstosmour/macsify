# ! You need to run `gh auth login` to authenticate with `GitHub CLI` before using functions using the `gh` package.

# Function to stash changes with a default name.
# Usage:
#   git_stash "Stash message" or git_stash
function git_stash
    if test -n "$argv[1]"
        set name "$argv[1]"
    else
        set name (date +'%d_%m_%YT%H_%M_%S')
    end

    git stash push -u -m "$name"
end


# Function to get the default branch.
# Usage:
#   git_get_default_branch
function git_get_default_branch
    set default_branch ""

    # Attempt to get the default branch from the remote repository
    set default_branch (git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
    if test -n "$default_branch"
        set default_branch "origin/$default_branch"
    else
        log_error "Could not determine the default branch!"
        return 1
    end

    echo "$default_branch"
end

# Function to fetch and rebase the current branch onto default branch with autostash enabled by default.
# Usage:
#   git_fetch_and_rebase optional_branch/"" true/false
function git_fetch_and_rebase
    set branch_to_rebase_onto ""
    set autostash_enabled "true"

    # Parse arguments.
    if test -n "$argv[1]"
        set branch_to_rebase_onto "$argv[1]"
    end

    if test -n "$argv[2]"
        set autostash_enabled "$argv[2]"
    end

    # Determine branch to rebase onto.
    if test -z "$branch_to_rebase_onto"
        # Get the default branch.
        set branch_to_rebase_onto (git_get_default_branch)

        # Check if the `git_get_default_branch` function succeeded.
        if test $status -ne 0
            log_error "Failed to determine the default branch!"
            return 1
        end
    else
        # Fetch the specific branch if provided
        git fetch origin $branch_to_rebase_onto
        set branch_to_rebase_onto "origin/$branch_to_rebase_onto"
    end


    # Check for uncommitted changes if autostash is disabled.
    if test "$autostash_enabled" = "false"
        if not git diff-index --quiet HEAD --
            log_error "Commit or stash your uncommitted changes before rebasing!"
            return 1
        end
    end

    log_info "Fetching and rebasing onto `$branch_to_rebase_onto`..."

    # Perform fetch and rebase with or without autostash.
    if test "$autostash_enabled" = "true"
        git fetch --all --prune && git rebase -i "$branch_to_rebase_onto" --autosquash --autostash
    else
        git fetch --all --prune && git rebase -i "$branch_to_rebase_onto" --autosquash
    end
end

# Function to choose commit to fixup.
# Pressing:
#   - ENTER will fixup the commit
#   - TAB will show the commit changes
#   - ? will toggle the preview
# Usage:
#   git_auto_fix_up
function git_auto_fix_up
    # Get the name of the current branch.
    set current_branch (git rev-parse --abbrev-ref HEAD)

    # Get the default branch.
    set default_branch (git_get_default_branch)
    if test $status -ne 0
        return 1
    end

    # Get the log of the current branch excluding commits from the upstream branch.
    set -l commits_list (git log --oneline --pretty=format:'%h | %s' --no-merges $default_branch..$current_branch | string split '\n')

    # Check if the commits list is empty.
    if test -z "$commits_list"
        echo "No commits found!"
        return 1
    end

    # Loop through the array.
    for line in $commits_list
        # Get commit hash and message.
        set commit_hash (echo $line | awk '{print $1}')
        set commit_message (echo $line | cut -d' ' -f3-)

        # Exclude lines where commit message starts with fixup!
        if not string match -q 'fixup!*' "$commit_message"

            # Print the commit hash and message.
            echo -e "$BOLD_YELLOW$commit_hash$NO_COLOR $BOLD_GREEN|$NO_COLOR $commit_message"
        end
    end | fzf --multi --ansi --bind 'enter:execute(git commit --fixup {1} --no-verify)+abort,tab:execute(git diff {1}^! | less -R),?:toggle-preview' --preview '

        # Keep the commit hash and message.
        set commit_hash {1}
        set commit_message (echo {2..} | cut -d"|" -f2- | sed "s/^ //")

        # Get the author, date, and files paths for the commit.
        set author (git show -s --format="%an" $commit_hash)
        set date (git show -s --format="%ad" --date=format-local:"on %d/%m/%Y at %H:%M:%S" $commit_hash)
        set files (git diff-tree --no-commit-id --name-only -r $commit_hash)

        # Color constants are not working in the preview window so we use the hardcoded ANSI escape codes.
        # Add "- " in front of each file line with green color.
        set formatted_files ""
        for file in $files
            set formatted_files "$formatted_files\e[1;32m-\e[0m $file\n"
        end

        echo -e "\e[1;33mHash:\e[0m $commit_hash"
        echo -e "\e[1;33mMessage:\e[0m $commit_message\n"
        echo -e "\e[1;36mAuthor:\e[0m $author"
        echo -e "\e[1;36mDate:\e[0m $date\n"

        # Show "Files:" and the list of files only if there are any files.
        if test -n "$files"
            echo -e "\e[1;32mFiles:\e[0m"
            echo -e "$formatted_files"
        end
    ' --preview-window=right:50%:hidden:wrap

    # Return success status regardless of fzf's exit status
    return 0
end

# Function to show/list git stashes and interact with them using fzf.
# Pressing:
#   - ENTER will apply the stash
#   - DELETE will drop the stash
#   - TAB will show the file changes
#   - ? will toggle the preview
# Usage:
#   git_stash_list
function git_stash_list
    # Get the stash list as an array.
    set -l stash_list (git stash list -n 50 --pretty=format:'%h|%s' | string split '\n')

    # Check if the stash list is empty.
    if test -z "$stash_list"
        log_error "No stashes found!"
        return 1
    end

    # Loop through the array.
    for line in $stash_list
        # Extract the stash hash by splitting based on "|".
        set stash_hash (echo "$line" | cut -d'|' -f1 | xargs)

        # Extract the stash message and keep it clean, without the branch.
        set stash_message (echo "$line" | cut -d'|' -f2- | xargs)
        set stash_message (echo "$stash_message" | sed 's/^On [^:]*: //')

        # Print the branch related to the stash and its message.
        echo -e "$BOLD_YELLOW$stash_hash$NO_COLOR $BOLD_GREEN|$NO_COLOR $stash_message"
    end | fzf --ansi --bind 'enter:execute(git stash apply (git log -g stash --format="%h %gd" | grep -m 1 {1} | awk "{print \$2}"))+abort,delete:execute(git stash drop (git log -g stash --format="%h %gd" | grep -m 1 {1} | awk "{print \$2}"))+abort,tab:execute(git stash show -p {1} | less -R),?:toggle-preview' --preview '
        # Extract stash hash and message from the selection.
        set stash_hash {1}
        set stash_message (echo {2..} | cut -d"|" -f2- | sed "s/^ //")

        # Get the stash index in the stash@{index} format.
        set stash_index (git log -g stash --format="%h %gd" | grep -m 1 "$stash_hash" | awk "{print \$2}")

        # Get the branch from git stash list excluding the stash message.
        set branch (git stash list --pretty=format:"%s" | grep -m 1 "$stash_message" | sed "s/.*On \(.*\): $stash_message/\1/" | xargs)

        # Get the date of the stash.
        set date (git show -s --format="%ad" --date=format-local:"%d/%m/%Y at %H:%M:%S" $stash_hash)

        # Get the list of files affected by the stash.
        set files (git stash show -p $stash_hash --name-only)

        # Color constants are not working in the preview window so we use the hardcoded ANSI escape codes.
        # Add "- " in front of each file line with green color.
        set formatted_files ""
        for file in $files
            set formatted_files "$formatted_files\e[1;32m-\e[0m $file\n"
        end

        echo -e "\e[1;33mIndex:\e[0m $stash_index"
        echo -e "\e[1;33mHash:\e[0m $stash_hash"
        echo -e "\e[1;33mBranch:\e[0m $branch\n"
        echo -e "\e[1;36mMessage:\e[0m $stash_message"
        echo -e "\e[1;36mDate:\e[0m $date\n"

        # Show "Files:" and the list of files only if there are any files.
        if test -n "$files"
            echo -e "\e[1;32mFiles:\e[0m"
            echo -e "$formatted_files"
        end
    ' --preview-window=right:50%:hidden:wrap

    # Return success status regardless of `fzf`'s exit status.
    return 0
end

# Function to show git log for the current branch and interact with it using fzf.
# Pressing:
#   - ENTER will reset the current branch to the selected commit
#   - TAB will show the commit changes
#   - ? will toggle the preview
# Usage:
#   git_log_current_branch
function git_log_current_branch
    # Get the name of the current branch.
    set current_branch (git rev-parse --abbrev-ref HEAD)

    # Get the base branch.
    set default_branch (git_get_default_branch)
    if test $status -ne 0
        return 1
    end

    # Get the log of the current branch excluding commits from the upstream branch.
    set -l log_list (git log --oneline --pretty=format:'%h | %s' $default_branch..$current_branch | string split '\n')

    # Check if the log list is empty.
    if test -z "$log_list"
        echo "No commits found!"
        return 1
    end

    # Loop through the array.
    for line in $log_list
        # Extract the commit hash and message.
        set commit_hash (echo "$line" | awk '{print $1}')
        set commit_message (echo "$line" | cut -d' ' -f3-)

        # Print the commit hash and message.
        echo -e "$BOLD_YELLOW$commit_hash$NO_COLOR $BOLD_GREEN|$NO_COLOR $commit_message"
    end | fzf --ansi --bind 'enter:execute(git reset --hard {1})+abort,tab:execute(git diff {1}^! | less -R),?:toggle-preview' --preview '
        # Extract commit hash and message from the selection.
        set commit_hash {1}
        set commit_message (echo {2..} | cut -d"|" -f2- | sed "s/^ //")

        # Get the author, date, and files paths for the commit.
        set author (git show -s --format="%an" $commit_hash)
        set date (git show -s --format="%ad" --date=format-local:"%d/%m/%Y at %H:%M:%S" $commit_hash)
        set files (git diff-tree --no-commit-id --name-only -r $commit_hash)

        # Color constants are not working in the preview window so we use the hardcoded ANSI escape codes.
        # Add "- " in front of each file line with green color.
        set formatted_files ""
        for file in $files
            set formatted_files "$formatted_files\e[1;32m-\e[0m $file\n"
        end

        echo -e "\e[1;33mHash:\e[0m $commit_hash"
        echo -e "\e[1;33mMessage:\e[0m $commit_message\n"
        echo -e "\e[1;36mAuthor:\e[0m $author"
        echo -e "\e[1;36mDate:\e[0m $date\n"

        # Show "Files:" and the list of files only if there are any files.
        if test -n "$files"
            echo -e "\e[1;32mFiles:\e[0m"
            echo -e "$formatted_files"
        end
    ' --preview-window=right:50%:hidden:wrap

    # Return success status regardless of `fzf`'s exit status.
    return 0
end

# Function to show all branches not merged or deleted and interact with them using fzf.
# Pressing:
#   - ENTER will checkout to the selected branch
#   - DELETE will delete the selected branch
#   - TAB will show the diff of the selected branch
#   - ? will toggle the preview and show more details
# Usage:
#   git_list_branches
function git_list_branches
    # Get the default branch.
    set default_branch (git_get_default_branch)
    if test $status -ne 0
        return 1
    end

    # Get the current branch.
    set current_branch (git branch --show-current)

    # Get all local and remote branches as arrays.
    set -l all_branches (git branch -a --format='%(refname:short)')
    set -l merged_branches (git branch -a --merged $default_branch | sed 's/^[* ]*//')
    set -l local_branches (git branch --format='%(refname:short)')
    set -l not_pushed_local_branches (git for-each-ref --format="%(refname:short) %(push:track)" refs/heads | grep '\[gone\]' | awk '{print $1}')

    # Remove merged branches from all_branches.
    set -l branch_list
    for b in $all_branches
        set found 0
        for m in $merged_branches
            if test "$b" = "$m"
                set found 1
                break
            end
        end
        if test $found -eq 0
            set branch_list $branch_list $b
        end
    end

    # Remove remote branches that have a corresponding local branch.
    set -l branch_list2
    for b in $branch_list
        set skip 0
        for l in $local_branches
            if test "$b" = "origin/$l"
                set skip 1
                break
            end
        end
        if test $skip -eq 0
            set branch_list2 $branch_list2 $b
        end
    end

    # Exclude origin/HEAD.
    set -l branch_list3
    for b in $branch_list2
        if test "$b" != "origin/HEAD"
            set branch_list3 $branch_list3 $b
        end
    end

    # Add not pushed local branches.
    for b in $not_pushed_local_branches
        if not contains $b $branch_list3
            set branch_list3 $branch_list3 $b
        end
    end

    # Remove empty entries.
    set -l final_branches
    for b in $branch_list3
        if test -n "$b"
            set final_branches $final_branches $b
        end
    end

    if test (count $final_branches) -eq 0
        echo "No branches found!"
        return 1
    end

    for line in $final_branches
        if test "$line" = "$current_branch"
            echo -e "$BOLD_YELLOW$line$NO_COLOR"
        else
            echo -e "$BOLD_GREEN$line$NO_COLOR"
        end
    end | fzf --ansi --bind 'enter:execute(git checkout {1})+abort,delete:execute(git branch -D {1})+abort,tab:execute(git diff {1} | less -R),?:toggle-preview' --preview '
        set branch_name {1}
        set author (git log -1 --pretty=format:"%an" $branch_name)
        set date (git log -1 --pretty=format:"%ad" --date=format-local:"%d/%m/%Y at %H:%M:%S" $branch_name)
        set files (git ls-tree -r $branch_name --name-only)
        set formatted_files ""
        for file in $files
            set formatted_files "$formatted_files\e[1;32m-\e[0m $file\n"
        end
        echo -e "\e[1;33mBranch:\e[0m $branch_name\n"
        echo -e "\e[1;36mAuthor:\e[0m $author"
        echo -e "\e[1;36mDate:\e[0m $date\n"
        if test -n "$files"
            echo -e "\e[1;32mFiles:\e[0m"
            echo -e "$formatted_files"
        end
    ' --preview-window=right:50%:hidden:wrap

    # Always return 0 so that escape/abort does not show as error.
    return 0
end

# Function to cherry-pick specific commits from different branches.
# Show a list of the branch | commit hash | commit message.
# Pressing:
#   - ENTER will cherry-pick the commit
#   - ? will toggle the preview and show more details
# Usage:
#   git_cherry_pick_commit
function git_cherry_pick_commit
    # Get the current branch.
    set current_branch (git branch --show-current)

    # Get the list of commits from all remote branches except the current one.
    set -l commits_list (git log --oneline --pretty=format:'%h | %s' --all --remotes | grep -v "origin/$current_branch" | string split '\n')

    # Check if the commit list is empty.
    if test -z "$commits_list"
        echo "No commits found!"
        return 1
    end

    # Loop through the array.
    for line in $commits_list
        # Get commit hash and message.
        set commit_hash (echo "$line" | awk '{print $1}')
        set commit_message (echo "$line" | cut -d' ' -f3-)

        # Print the commit hash and message.
        echo -e "$BOLD_YELLOW$commit_hash$NO_COLOR $BOLD_GREEN|$NO_COLOR $commit_message"
    end | fzf --ansi --bind 'enter:execute(git cherry-pick {1})+abort,?:toggle-preview' --preview '
        # Keep the commit hash and message.
        set commit_hash {1}
        set commit_message (echo {2..} | cut -d"|" -f2- | sed "s/^ //")

        # Get the branch, author, date, and files paths for the commit.
        set branch (git branch -a --contains $commit_hash | grep "remotes/origin/" | sed "s#remotes/##")

        set author (git show -s --format="%an" $commit_hash)
        set date (git show -s --format="%ad" --date=format-local:"%d/%m/%Y at %H:%M:%S" $commit_hash)
        set files (git diff-tree --no-commit-id --name-only -r $commit_hash)

        # Color constants are not working in the preview window so we use the hardcoded ANSI escape codes.
        # Add "- " in front of each file line with green color.
        set formatted_files ""
        for file in $files
            set formatted_files "$formatted_files\e[1;32m-\e[0m $file\n"
        end

        echo -e "\e[1;33mHash:\e[0m $commit_hash"
        echo -e "\e[1;33mBranch:\e[0m $branch"
        echo -e "\e[1;33mMessage:\e[0m $commit_message\n"
        echo -e "\e[1;36mAuthor:\e[0m $author"
        echo -e "\e[1;36mDate:\e[0m $date\n"

        # Show "Files:" and the list of files only if there are any files.
        if test -n "$files"
            echo -e "\e[1;32mFiles:\e[0m"
            echo -e "$formatted_files"
        end
    ' --preview-window=right:50%:hidden:wrap
end

# Function to merge the current branch to default branch.
# Usage:
#   git_merge_to_default_branch [branch_name] [pr_number]
function git_merge_to_default_branch
    set remote "origin"
    set current_branch ""
    set upstream_branch ""
    set default_branch ""
    set branch_to_be_merged ""
    set new_commits_count 0
    set no_ff_option ""
    set merge_commit_title ""
    set merge_commit_body ""

    # Safety check: Ensure no rebase is ongoing.
    if test -d (git rev-parse --git-dir)/rebase-merge -o -d (git rev-parse --git-dir)/rebase-apply
        log_error "Rebase in progress, operation stopped!"
        return 1
    end

    # Step 1: Checkout specified branch if provided.
    if test -n "$argv[1]"
        log_info "Checking out `$argv[1]` branch..."
        git checkout "$argv[1]"
    end

    set current_branch (git rev-parse --abbrev-ref HEAD)
    log_info "Currently on `$current_branch` branch."

    # Step 2: Determine remote branch name.
    set upstream_branch (git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null | sed 's|^origin/||'; or echo "$current_branch")
    if not git ls-remote --heads --exit-code "$remote" "$upstream_branch" >/dev/null 2>&1
        set upstream_branch "$current_branch"
        if not git ls-remote --heads --exit-code "$remote" "$upstream_branch" >/dev/null 2>&1
            read -P "Please enter the branch name for fetch/push operations: " upstream_branch
        end
    end
    log_info "Tracking the remote branch `$upstream_branch`..."

    # Fetch and rebase current branch onto master/main.
    git_fetch_and_rebase "" false
    if test $status -ne 0
        log_error "Rebase failed, resolve conflicts/errors before running the script again!"
        return 1
    end

    # Push the auto-squashed history so FETCH_HEAD later is clean.
    git push --force-with-lease "$remote" "$upstream_branch"

    # Get the base branch using the `git_get_default_branch` function.
    set default_branch (git_get_default_branch)
    set branch_to_be_merged "$remote/$upstream_branch"
    set local_branch (string replace "origin/" "" "$default_branch")

    git checkout "$local_branch"
    git reset --hard "$default_branch"
    git fetch "$remote" "$current_branch"

    set new_commits_count (git rev-list --count "$default_branch..FETCH_HEAD")
    if test "$new_commits_count" -ge 1
        set no_ff_option "--no-ff"
        set merge_commit_title "Merge branch `$current_branch`"
        if test -n "$argv[2]"
            set merge_commit_body "Closes #$argv[2]"
        end
    end

    log_info "The following commits will be merged from `$current_branch` to `$default_branch`:"
    git --no-pager log --decorate --graph --oneline "$default_branch..FETCH_HEAD"

    log_warning "Do you want to merge and push these commits to `$default_branch`? (Y/N):"
    read user_confirm
    if test "$user_confirm" = "y" -o "$user_confirm" = "Y"
        # Build merge arguments array.
        set merge_args "FETCH_HEAD"
        if test -n "$no_ff_option"
            set merge_args $merge_args $no_ff_option
        end
        if test -n "$merge_commit_title"
            set merge_args $merge_args -m "$merge_commit_title"
            if test -n "$merge_commit_body"
                set merge_args $merge_args -m "$merge_commit_body"
            end
        end

        git merge $merge_args

        if test $status -ne 0
            log_error "Merge failed!"
            git checkout "$current_branch"
            return 1
        end

        git push "$remote" "$local_branch"
        if test $status -ne 0
            log_error "Push to `$default_branch` failed!"
            git reset --hard HEAD^
            git checkout "$current_branch"
            return 1
        end
        log_success "Push to `$default_branch` was successful."
    else
        log_info "Merge and push to `$default_branch` was aborted."
        git checkout "$current_branch"
    end
end

# Function to set upstream branch for current branch.
# Usage:
#   git_add_remote_branch
function git_add_remote_branch
    set current_branch (git rev-parse --abbrev-ref HEAD)
    set remote "origin"

    log_info "Setting upstream for `$current_branch` to `$remote/$current_branch`..."
    git branch --set-upstream-to="$remote/$current_branch" "$current_branch"

    if test $status -eq 0
        log_success "Successfully set upstream for `$current_branch` to `$remote/$current_branch`."
        return 0
    else
        log_error "Failed to set upstream for `$current_branch`!"
        return 1
    end
end

# Function to list and interact with GitHub PRs that need review.
# Pressing:
#   - ENTER will open the PR in the default browser
# Usage:
#   github_pr_reviews
function github_pr_reviews
    # Fetch open PRs where user is involved but is not the author.
    set prs_list (gh pr list --state open --search "involves:@me -author:@me" --json number,title,author,reviews,url --template '{{range .}}{{.number}}|{{.title}}|{{.author.login}}|{{len .reviews}}|{{.url}}{{"\n"}}{{end}}' | string split '\n')

    # Check if the PR list is empty.
    if test -z "$prs_list"
        echo "No pull requests found!"
        return 1
    end

    # Loop through the array.
    for line in $prs_list
        set pr_number (echo "$line" | cut -d'|' -f1)
        set pr_title (echo "$line" | cut -d'|' -f2)
        set pr_author (echo "$line" | cut -d'|' -f3)
        set pr_url (echo "$line" | cut -d'|' -f5)

        # Print PR info (spaces won't be parsed as delimiters).
        echo -e "\033[1;33m$pr_number\033[0m \033[1;32m|\033[0m \033[1;33m$pr_author\033[0m \033[1;32m|\033[0m $pr_title"
    end | fzf --ansi --bind 'enter:execute(gh pr view (echo {} | grep -oE "[0-9]+" | head -1) --json url --template "{{.url}}" | xargs open)+abort' --preview '
        # Extract PR number from the line
        set pr_number (echo {} | grep -oE "[0-9]+" | head -1)

        # Fetch full PR details
        gh pr view $pr_number --json number,title,author,createdAt,updatedAt,body,commits,comments,reviews,headRefName,baseRefName --template "PR #{{.number}}\nTitle: {{.title}}\n\nAuthor: {{.author.login}}\nCreated: {{.createdAt}}\nUpdated: {{.updatedAt}}\n\nBranch: {{.headRefName}} → {{.baseRefName}}\nStats: {{len .commits}} commits | {{len .comments}} comments | {{len .reviews}} reviews\n\nDescription:\n{{.body}}"
    ' --preview-window=right:50%:hidden:wrap
end

# Function to list and interact with my GitHub PRs (open or closed).
# Pressing:
#   - ENTER will open the PR in the default browser
#   - ESC to exit
# Usage:
#   github_my_prs [open|closed]
function github_my_prs
    set state "$argv[1]"

    if test -z "$state"
        echo "Usage: github_my_prs [open|closed]"
        return 1
    end

    # Build the search query based on state.
    set search_query ""
    set error_msg ""

    if test "$state" = "open"
        set search_query "assignee:@me is:open"
        set error_msg "No open pull requests found!"
    else if test "$state" = "closed"
        set search_query "is:closed assignee:@me"
        set error_msg "No closed pull requests found!"
    else
        echo "Invalid state: $state. Use 'open' or 'closed'"
        return 1
    end

    # Fetch PRs assigned to user with the specified state.
    set prs_list (gh pr list --state $state --search "$search_query" --json number,title,url --template '{{range .}}{{.number}}|{{.title}}|{{.url}}{{"\n"}}{{end}}' | string split '\n')

    # Check if the PR list is empty.
    if test -z "$prs_list"
        echo "$error_msg"
        return 1
    end

    # Loop through the array.
    for line in $prs_list
        set pr_number (echo "$line" | cut -d'|' -f1)
        set pr_title (echo "$line" | cut -d'|' -f2)

        # Print PR ID and title.
        echo -e "\033[1;33m$pr_number\033[0m \033[1;32m|\033[0m $pr_title"
    end | fzf --ansi --bind 'enter:execute(gh pr view (echo {} | grep -oE "[0-9]+" | head -1) --json url --template "{{.url}}" | xargs open)+abort'
end

# Function to create a `GitHub PR` with a predefined template.
# If no title is provided, the current branch name will be used.
# Upon successful creation, the PR link will be displayed.
# Usage:
#   github_create_pr "PR Title"
#   github_create_pr (uses branch name as title)
function github_create_pr
    # Use provided title or branch name if no title given.
    set pr_title "$argv[1]"
    if test -z "$pr_title"
        set pr_title (git rev-parse --abbrev-ref HEAD)
    end

    set pr_body "**What**:

This PR ...

**Why**:

Resolves [task_id](https://link/to/task_id).

**How**:

-

**Testing**:

-"

    log_info "Creating '$pr_title' PR..."

    # Create the `PR` and get the `URL`.
    set pr_url (gh pr create --title "$pr_title" --body "$pr_body" 2>&1)

    if test $status -eq 0
        log_success "PR created successfully!"
        log_info "PR URL: $pr_url"
        return 0
    else
        log_error "Failed to create PR!"
        return 1
    end
end

# Function to fetch all, ensure correct upstream, and pull.
# Handles the common case where a local branch tracks the wrong upstream while a matching remote branch exists.
# Prints a warning if local and remote have diverged.
# Usage:
#   git_fetch_pull_upstream
function git_fetch_pull_upstream
    git fetch --all --prune; or return 1

    set -l branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if test "$branch" = "HEAD"
        log_warning "Detached HEAD, skipping upstream check."
    else if git rev-parse --verify -q "origin/$branch" >/dev/null 2>&1
        set -l expected "refs/remotes/origin/$branch"
        set -l actual (git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>/dev/null; or echo "")

        if test "$actual" != "$expected"
            set -l divergence (git rev-list --left-right --count "HEAD...origin/$branch" 2>/dev/null)
            if test "$status" -eq 0
                set -l ahead (echo "$divergence" | awk '{print $1}')
                set -l behind (echo "$divergence" | awk '{print $2}')
                if test "$ahead" -gt 0 -a "$behind" -gt 0
                    log_warning "Local and remote '$branch' have diverged ($ahead ahead, $behind behind)."
                    log_info "Setting upstream to 'origin/$branch'..."
                end
            end

            log_info "Setting upstream to 'origin/$branch'..."
            git branch -u "origin/$branch"; or return 1
        end
    end

    git pull
end

# Function to see lines of code per author for a file.
# Usage:
#   git_blame_stats <filename>
function git_blame_stats
    if test -z "$argv[1]"
        log_error "Please provide a filename"
        return 1
    end

    git blame --line-porcelain "$argv[1]" | grep "^author " | grep -v "^author-mail" | sed 's/^author //' | sort | uniq -c | sort -n | awk '{num=$1; $1=""; gsub(/^[[:space:]]+/, ""); printf "%s | %d\n", $0, num}'
end

# Function to add `Co-authored-by` trailers to all commits on a feature branch.
# Fetches team members from `GitHub` org, resolves names/emails,
# and lets the user select co-authors interactively.
# Usage:
#   git_set_coauthors
function git_set_coauthors
    set current_branch (git rev-parse --abbrev-ref HEAD)

    set default_branch (git_get_default_branch)
    if test $status -ne 0
        return 1
    end

    set local_default (string replace "origin/" "" "$default_branch")

    if test "$current_branch" = "main" -o "$current_branch" = "master" -o "$current_branch" = "$local_default"
        log_error "You are on the default branch!"
        log_warning "Switch to a feature branch first."
        return 1
    end

    set working_tree_status (git status --porcelain)
    if test -n "$working_tree_status"
        log_error "Working tree is not clean!"
        log_warning "Commit or stash local changes before running this function."
        return 1
    end

    set all_commits (git log --reverse --no-merges --format="%h %s" "$default_branch..$current_branch" | string split '\n')
    if test -z "$all_commits"
        log_error "No commits found on this branch ahead of default!"
        return 1
    end

    set merge_count (git rev-list --count --merges "$default_branch..$current_branch")
    if test "$merge_count" -gt 0
        log_warning "Found $merge_count merge commit(s) in this branch range."
        log_warning "Merge commits are not selectable and will be left untouched."
    end

    set display_commits
    for line in $all_commits
        if not string match -qi '*fixup!*' "$line"
            set display_commits $display_commits "$line"
        end
    end

    if test (count $display_commits) -eq 0
        log_error "No non-fixup commits found on this branch!"
        return 1
    end

    set total_count (count $all_commits)
    set display_count (count $display_commits)
    log_info "Found $display_count commit(s)."

    echo ""
    read -P "Team name: " team_name
    if test $status -ne 0; return 1; end
    if test -z "$team_name"
        log_error "Team name is required."
        return 1
    end
    set team_name (string lower "$team_name")

    echo ""
    log_info "Deriving repository details..."
    set repo_org (git remote get-url origin 2>/dev/null | sed -n 's/.*github.com[:\/]\([^\/]*\)\/.*/\1/p')
    if test -z "$repo_org"
        read -P "GitHub organization: " repo_org
        if test $status -ne 0; return 1; end
        if test -z "$repo_org"
            log_error "Organization is required."
            return 1
        end
    end
    set repo_org (string lower "$repo_org")

    set email_domain (git log --all --format="%ae" 2>/dev/null | sort -u | grep -v 'users.noreply.github.com' | sed 's/.*@//' | sort | uniq -c | sort -rn | head -1 | sed 's/^ *[0-9]* //')
    if test -z "$email_domain"
        read -P "Email domain: " email_domain
        if test $status -ne 0; return 1; end
        if test -z "$email_domain"
            log_error "Email domain is required."
            return 1
        end
    end

    log_info "Fetching '$team_name' team members from '$repo_org'..."
    set members_json (gh api /orgs/$repo_org/teams/$team_name/members 2>&1)
    if test $status -ne 0
        log_error "Failed to fetch team members: $members_json"
        return 1
    end

    set my_login (gh api /user -q '.login' 2>/dev/null)
    set logins (echo "$members_json" | jq -r '.[].login' | grep -v "^$my_login\$")
    if test (count $logins) -eq 0
        log_error "No team members found."
        return 1
    end

    set coauthors
    for login in $logins
        if test -z "$login"; continue; end

        set name (gh api /users/$login -q '.name // .login' 2>/dev/null)
        if test -z "$name"
            set name "$login"
        end

        set matched (git log --all --format="%an <%ae>" 2>/dev/null | sort -u | grep -i -F "$name <" | grep -im1 -F "@$email_domain")
        set email ""
        if test -n "$matched"
            set email (echo "$matched" | sed 's/.*<\(.*\)>/\1/')
        end

        if test -z "$email"
            set lastname (echo "$name" | awk '{print $NF}')
            if test -n "$lastname"
                set matched (git log --all --format="%an <%ae>" 2>/dev/null | sort -u | grep -i -F "$lastname <" | grep -im1 -F "@$email_domain")
                if test -n "$matched"
                    set email (echo "$matched" | sed 's/.*<\(.*\)>/\1/')
                end
            end
        end

        if test -z "$email"
            set matched (git log --all --format="%an <%ae>" 2>/dev/null | sort -u | grep -i "$login" | grep -im1 -F "@$email_domain")
            if test -n "$matched"
                set email (echo "$matched" | sed 's/.*<\(.*\)>/\1/')
            end
        end

        if test -z "$email"
            echo ""
            read -P "Email for $name ($login): " user_email
            if test $status -ne 0; return 1; end
            if test -z "$user_email"
                log_warning "Skipping $name"
                continue
            end
            set email "$user_email"
        end

        set coauthors $coauthors "$name <$email>"
    end

    if test (count $coauthors) -eq 0
        log_error "No co-authors resolved."
        return 1
    end

    log_info "Team members from '$team_name':"
    for i in (seq (count $coauthors))
        echo -e "  $BOLD_YELLOW$i)$NO_COLOR $coauthors[$i]"
    end

    echo ""
    log_info "Select co-authors, use TAB to multi-select and ENTER to confirm:"
    read -P "Press Enter to continue... "
    if test $status -ne 0; return 1; end
    echo ""
    set fzf_input
    for i in (seq (count $coauthors))
        set fzf_input $fzf_input "$i|$coauthors[$i]"
    end

    set selected_raw (printf '%s\n' $fzf_input | fzf --multi -d'|' --with-nth 2.. 2>/dev/null)
    set fzf_status $status
    if test $fzf_status -ne 0; return 1; end
    set selected_raw (string split '\n' -- $selected_raw)

    set selected_coauthors
    for line in $selected_raw
        if test -n "$line"
            set idx (echo "$line" | cut -d'|' -f1)
            if test -n "$idx" -a "$idx" -ge 1 -a "$idx" -le (count $coauthors)
                if not contains "$idx" $selected_coauthors
                    set selected_coauthors $selected_coauthors $idx
                end
            end
        end
    end

    if test (count $selected_coauthors) -eq 0
        log_error "No co-authors selected."
        return 1
    end

    echo ""
    log_success "Selected co-authors:"
    for idx in $selected_coauthors
        echo "  - $coauthors[$idx]"
    end

    set exec_cmd "git log -1 --pretty=%B | sed '/^Co-authored-by:/d' | git interpret-trailers"
    for idx in $selected_coauthors
        set coauthor "$coauthors[$idx]"
        set exec_cmd "$exec_cmd --trailer 'Co-authored-by: $coauthor'"
    end
    set exec_cmd "$exec_cmd | git commit --amend -F -"

    echo ""
    log_info "Select commits to add co-author(s) to, use TAB to multi-select and ENTER to confirm:"
    set selection_commits
    for idx in (seq (count $display_commits) -1 1)
        set selection_commits $selection_commits "$display_commits[$idx]"
    end

    read -P "Press Enter to continue... "
    if test $status -ne 0; return 1; end
    echo ""
    set selected_lines (for line in $selection_commits
        set hash (echo "$line" | awk '{print $1}')
        set subject (echo "$line" | cut -d' ' -f2-)
        echo -e "$BOLD_YELLOW$hash$NO_COLOR $BOLD_GREEN|$NO_COLOR $subject"
    end | fzf --multi --ansi --bind '?:toggle-preview' --preview '
        set commit_hash {1}
        git diff-tree --no-commit-id --name-only -r $commit_hash | while read -l f; echo -e "\e[1;32m-\e[0m $f"; end
    ' --preview-window=right:50%:hidden:wrap)
    set fzf_status $status
    if test $fzf_status -ne 0; return 1; end
    set selected_lines (string split '\n' -- $selected_lines)

    set selected_hashes
    for line in $selected_lines
        if test -n "$line"
            set hash (echo "$line" | string replace -ra '\e\[[0-9;]*m' '' | awk '{print $1}')
            set selected_hashes $selected_hashes "$hash"
        end
    end

    if test (count $selected_hashes) -eq 0
        log_error "No commits selected."
        return 1
    end

    echo ""
    log_success "Selected commits:"
    for line in $selection_commits
        set hash (echo "$line" | awk '{print $1}')
        set subject (echo "$line" | cut -d' ' -f2-)
        if contains "$hash" $selected_hashes
            echo -e "$BOLD_YELLOW$hash$NO_COLOR $BOLD_GREEN|$NO_COLOR $subject"
        end
    end

    set final_count (count $selected_hashes)
    log_warning "About to add co-author(s) to $final_count commit(s) on '$current_branch':"
    for idx in $selected_coauthors
        echo "  - $coauthors[$idx]"
    end
    echo ""
    read -P "Continue? (y/N): " confirm
    if test $status -ne 0; return 1; end
    if test "$confirm" != "y" -a "$confirm" != "Y"
        log_info "Aborted."
        return 0
    end

    set backup_timestamp (date +'%Y%m%d_%H%M%S')
    set backup_branch "backup/$current_branch-before-coauthors-$backup_timestamp"
    log_info "Creating backup branch '$backup_branch'..."
    git branch "$backup_branch"
    if test $status -ne 0
        log_error "Failed to create backup branch '$backup_branch'."
        return 1
    end

    set base_commit (git merge-base "$default_branch" HEAD)
    set todo_file (mktemp /tmp/opencode-rebase-todo.XXXXXXXXXX)

    for line in $all_commits
        set hash (echo "$line" | awk '{print $1}')
        set subject (echo "$line" | cut -d' ' -f2-)
        echo "pick $hash $subject" >> $todo_file
        if contains "$hash" $selected_hashes
            echo "exec $exec_cmd" >> $todo_file
        end
    end

    log_info "Adding co-author(s) to the selected commits..."
    GIT_SEQUENCE_EDITOR="cp $todo_file" git rebase -i "$base_commit" --committer-date-is-author-date
    set rebase_status $status

    rm -f "$todo_file"

    if test $rebase_status -eq 0
        log_success "Co-author(s) added to $final_count commit(s) on '$current_branch'."
    else
        log_error "Rebase failed. Run 'git rebase --abort' to revert."
        return 1
    end
end
