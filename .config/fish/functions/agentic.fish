# Functions for agentic session management using fzf.
# Pressing:
#   - ENTER will resume the selected session
#   - DELETE will delete the session
#   - ? will toggle the preview
function claude_session_list
    set -l history_file ~/.claude/history.jsonl

    if not test -f "$history_file"
        log_error "No Claude history found!"
        return 1
    end

    set -l session_data (jq -rs --arg pwd "$PWD" '
        map(select(.sessionId != null)) |
        group_by(.sessionId) |
        map(
            (sort_by(.timestamp)) as $g |
            {
                sessionId: ($g | first | .sessionId),
                project:   ($g | last  | .project // ""),
                max_ts:    ($g | last  | .timestamp),
                min_ts:    ($g | first | .timestamp)
            }
        ) |
        sort_by((.project != $pwd), -.max_ts)[] |
        [.sessionId, (.project // ""), (.max_ts | tostring), (.min_ts | tostring)] |
        @tsv
    ' "$history_file" 2>/dev/null)

    if test (count $session_data) -eq 0
        log_error "No sessions found!"
        return 1
    end

    set -l output (for line in $session_data
        set -l fields (string split \t -- "$line")
        set -l session_id $fields[1]
        set -l project $fields[2]
        set -l max_ts $fields[3]
        set -l min_ts $fields[4]

        set -l enc (string replace -a '/' '-' -- "$project")
        set -l jsonl "$HOME/.claude/projects/$enc/$session_id.jsonl"

        if not test -f "$jsonl"
            continue
        end
        set -l short_id (string sub -l 8 -- "$session_id")
        set -l updated (date -r (math --scale=0 "$max_ts / 1000") '+%Y-%m-%d %H:%M' 2>/dev/null)
        set -l created (date -r (math --scale=0 "$min_ts / 1000") '+%Y-%m-%d %H:%M' 2>/dev/null)

        # Same precedence claude-hud uses for its statusline: a /rename'd
        # custom title always wins over the auto-generated slug.
        set -l custom_title (jq -r 'select(.type == "custom-title" and (.customTitle != null)) | .customTitle' "$jsonl" 2>/dev/null | tail -1)
        set -l session_name $custom_title
        if test -z "$session_name"
            set session_name (jq -r 'select(.slug != null) | .slug' "$jsonl" 2>/dev/null | tail -1)
        end
        test -n "$session_name"; or set session_name $short_id
        if test (string length -- "$session_name") -gt 60
            set session_name (string sub -l 57 -- "$session_name")"..."
        end

        if test "$project" = "$PWD"
            printf '%s\t%s\t\033[1;33m> %s\033[0m \033[1;32m|\033[0m %s\t%s\t%s\t%s\n' \
                "$jsonl" "$session_id" \
                "$short_id" "$session_name" \
                "$project" "$created" "$updated"
        else
            printf '%s\t%s\t\033[0;33m  %s\033[0m \033[0;32m|\033[0m %s\t%s\t%s\t%s\n' \
                "$jsonl" "$session_id" \
                "$short_id" "$session_name" \
                "$project" "$created" "$updated"
        end
    end | env SHELL=/bin/bash fzf --ansi --height=20 --delimiter='\t' --with-nth=3 \
        --expect=delete \
        --bind '?:toggle-preview' \
        --preview '
            sid={2}
            directory={4}
            created={5}
            updated={6}
            jsonl={1}
            [ -z "$directory" ] && directory=-
            model=-
            desc=-
            if [ -f "$jsonl" ]; then
                model=$(jq -r "select(.type == \"assistant\") | .message.model // empty" "$jsonl" 2>/dev/null | grep -v "^$" | head -1)
                [ -z "$model" ] && model=-
                desc=$(jq -rn "first(inputs | select(.type == \"user\")) | .message.content | if type == \"string\" then . elif type == \"array\" then (map(select(.type == \"text\") | .text) | first // \"-\") else \"-\" end" "$jsonl" 2>/dev/null | head -c 500)
                [ -z "$desc" ] && desc=-
            fi
            printf "\033[1;33mID:\033[0m %s\n" "$sid"
            printf "\033[1;33mDirectory:\033[0m %s\n" "$directory"
            printf "\033[1;33mCreated:\033[0m %s\n" "$created"
            printf "\033[1;33mUpdated:\033[0m %s\n\n" "$updated"
            printf "\033[1;34mModel:\033[0m %s\n\n" "$model"
            printf "\033[1;32mDescription:\033[0m %s\n" "$desc"
        ' --preview-window=right:50%:hidden:wrap)

    if test (count $output) -lt 2
        return 0
    end

    set -l key $output[1]
    set -l selected_line $output[2]
    set -l jsonl_path (echo "$selected_line" | cut -f1)
    set -l session_id (echo "$selected_line" | cut -f2)
    set -l project_dir (echo "$selected_line" | cut -f4)

    if test "$key" = delete -a -n "$session_id"
        test -f "$jsonl_path"; and rm -f "$jsonl_path"
        if test -f "$history_file"
            grep -v "\"sessionId\":\"$session_id\"" "$history_file" > "$history_file.tmp" 2>/dev/null
            mv "$history_file.tmp" "$history_file"
        end
        return 0
    end

    if test -n "$session_id"
        if test -n "$project_dir" -a -d "$project_dir"
            env -C "$project_dir" claude -r "$session_id"
        else
            claude -r "$session_id"
        end
    end

    return 0
end

function opencode_session_list
    set -l session_json (opencode session list --format json 2>/dev/null)
    if test -z "$session_json"
        log_error "No sessions found!"
        return 1
    end

    set -l session_data (echo "$session_json" | jq -r --arg pwd "$PWD" '
        sort_by((.directory != $pwd), -.updated) |
        .[] |
        [.id, (.title // ""), (.directory // "")] |
        @tsv
    ' 2>/dev/null)

    if test (count $session_data) -eq 0
        log_error "No sessions found!"
        return 1
    end

    set -l output (for line in $session_data
        set -l fields (string split \t -- "$line")
        set -l sid $fields[1]
        set -l title $fields[2]
        set -l directory $fields[3]

        if test "$directory" = "$PWD"
            printf '%s\t\033[1;33m> %s\033[0m \033[1;32m|\033[0m %s\n' "$sid" "$sid" "$title"
        else
            printf '%s\t\033[0;33m  %s\033[0m \033[0;32m|\033[0m %s\n' "$sid" "$sid" "$title"
        end
    end | env SHELL=/bin/bash fzf --ansi --height=20 --delimiter='\t' --with-nth=2.. \
        --expect=delete \
        --bind '?:toggle-preview' \
        --preview '
            sid={1}
            raw=$(opencode export "$sid" 2>/dev/null)
            if [ -z "$raw" ]; then printf "Session not found.\n"; exit 1; fi
            id=$(printf "%s" "$raw" | grep -oE "\"id\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 | cut -d"\"" -f4)
            directory=$(printf "%s" "$raw" | grep -oE "\"directory\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 | cut -d"\"" -f4)
            title=$(printf "%s" "$raw" | grep -oE "\"title\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 | cut -d"\"" -f4)
            created_ms=$(printf "%s" "$raw" | grep -oE "\"created\"[[:space:]]*:[[:space:]]*[0-9]+" | head -1 | grep -oE "[0-9]+")
            updated_ms=$(printf "%s" "$raw" | grep -oE "\"updated\"[[:space:]]*:[[:space:]]*[0-9]+" | head -1 | grep -oE "[0-9]+")
            provider_id=$(printf "%s" "$raw" | grep -oE "\"providerID\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 | cut -d"\"" -f4)
            model_id=$(printf "%s" "$raw" | grep -oE "\"modelID\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 | cut -d"\"" -f4)
            [ -z "$id" ] && id=-
            [ -z "$directory" ] && directory=-
            [ -z "$title" ] && title=-
            [ -z "$provider_id" ] && provider_id=-
            [ -z "$model_id" ] && model_id=-
            [ -z "$created_ms" ] && created_ms=0
            [ -z "$updated_ms" ] && updated_ms=0
            created=-; updated=-
            if [ "$created_ms" -gt 0 ] 2>/dev/null; then created=$(date -r $((created_ms / 1000)) "+%Y-%m-%d %H:%M:%S" 2>/dev/null); fi
            if [ "$updated_ms" -gt 0 ] 2>/dev/null; then updated=$(date -r $((updated_ms / 1000)) "+%Y-%m-%d %H:%M:%S" 2>/dev/null); fi
            model=-
            if [ "$provider_id" != "-" ] && [ "$model_id" != "-" ]; then model="$provider_id/$model_id"; elif [ "$provider_id" != "-" ]; then model="$provider_id"; fi
            desc=$(printf "%s" "$raw" | grep -E "^[[:space:]]+\"text\"[[:space:]]*:" | head -1 | sed "s/^[[:space:]]*\"text\"[[:space:]]*:[[:space:]]*\"//; s/\".*$//" | head -c 200)
            [ -z "$desc" ] && desc=-
            printf "\033[1;33mID:\033[0m %s\n" "$id"
            printf "\033[1;33mDirectory:\033[0m %s\n" "$directory"
            printf "\033[1;33mCreated:\033[0m %s\n" "$created"
            printf "\033[1;33mUpdated:\033[0m %s\n\n" "$updated"
            printf "\033[1;34mTitle:\033[0m %s\n" "$title"
            printf "\033[1;34mModel:\033[0m %s\n\n" "$model"
            printf "\033[1;32mDescription:\033[0m %s\n" "$desc"
        ' --preview-window=right:50%:hidden:wrap)

    if test (count $output) -lt 2
        return 0
    end

    set -l key $output[1]
    set -l selected_sid (echo "$output[2]" | cut -f1)

    if test "$key" = delete -a -n "$selected_sid"
        opencode session delete "$selected_sid"
        return 0
    end

    if test -n "$selected_sid"
        opencode -s "$selected_sid"
    end

    return 0
end

# Function to delete all Claude session transcripts and history entries for the current directory.
# Prompts for confirmation before deleting.
# Usage:
#   claude_delete_conversations
function claude_delete_conversations
    set -l history_file ~/.claude/history.jsonl

    if not test -f "$history_file"
        log_error "No Claude history found!"
        return 1
    end

    set -l session_ids (jq -rs --arg pwd "$PWD" '
        map(select(.sessionId != null and .project == $pwd)) |
        map(.sessionId) | unique[]
    ' "$history_file" 2>/dev/null)

    if test (count $session_ids) -eq 0
        log_error "No sessions found for $PWD!"
        return 1
    end

    set -l count (count $session_ids)
    log_warning "About to delete $count Claude session(s) for '$PWD'."
    read -P "Continue? (y/N): " confirm
    if test $status -ne 0; return 1; end
    if test "$confirm" != "y" -a "$confirm" != "Y"
        log_info "Aborted."
        return 0
    end

    set -l enc (string replace -a '/' '-' -- "$PWD")
    set -l project_dir "$HOME/.claude/projects/$enc"
    test -d "$project_dir"; and rm -rf "$project_dir"

    grep -vF "\"project\":\"$PWD\"" "$history_file" >"$history_file.tmp" 2>/dev/null
    mv "$history_file.tmp" "$history_file"

    log_success "Deleted $count Claude session(s)."
end

# Function to delete all OpenCode sessions for the current directory.
# Prompts for confirmation before deleting.
# Usage:
#   opencode_delete_conversations
function opencode_delete_conversations
    set -l session_ids (opencode session list --format json 2>/dev/null | jq -r --arg pwd "$PWD" '.[] | select(.directory == $pwd) | .id')

    if test (count $session_ids) -eq 0
        log_error "No sessions found for $PWD!"
        return 1
    end

    set -l count (count $session_ids)
    log_warning "About to delete $count OpenCode session(s) for '$PWD'."
    read -P "Continue? (y/N): " confirm
    if test $status -ne 0; return 1; end
    if test "$confirm" != "y" -a "$confirm" != "Y"
        log_info "Aborted."
        return 0
    end

    for id in $session_ids
        opencode session delete "$id"
    end

    log_success "Deleted $count OpenCode session(s)."
end

# Function to run Claude Code unattended, skipping permissions and commit signing.
# Signing goes through 1Password, whose approval prompt would stop the agent
# mid-task, so its commits stay unsigned and `versioning.md` has it re-sign the
# branch once, with the user's approval, before any push. The overrides reach
# this process only, every other terminal keeps signing.
# Usage:
#   claude_unattended [claude arguments]
function claude_unattended
    AGENTIC_UNSIGNED_COMMITS=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false claude --dangerously-skip-permissions $argv
end
