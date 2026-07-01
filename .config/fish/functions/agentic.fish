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

    set -l session_data (jq -rs '
        map(select(.sessionId != null)) |
        group_by(.sessionId) |
        map(
            (sort_by(.timestamp)) as $g |
            {
                sessionId:        ($g | first | .sessionId),
                project:          ($g | last  | .project // ""),
                max_ts:           ($g | last  | .timestamp),
                min_ts:           ($g | first | .timestamp),
                display_fallback: (($g | map(select((.display // "") | (. != "") and (startswith("/") | not))) | first | .display) // "")
            }
        ) |
        sort_by(-.max_ts)[] |
        [.sessionId, (.project // ""), (.max_ts | tostring), (.min_ts | tostring), (.display_fallback // "")] |
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
        set -l display_fallback $fields[5]

        set -l enc (string replace -a '/' '-' -- "$project")
        set -l jsonl "$HOME/.claude/projects/$enc/$session_id.jsonl"

        if not test -f "$jsonl"
            continue
        end
        set -l short_id (string sub -l 8 -- "$session_id")
        set -l updated (date -r (math --scale=0 "$max_ts / 1000") '+%Y-%m-%d %H:%M' 2>/dev/null)
        set -l created (date -r (math --scale=0 "$min_ts / 1000") '+%Y-%m-%d %H:%M' 2>/dev/null)

        set -l display (
            if test -f "$jsonl"
                head -50 "$jsonl" | jq -r '
                    select(.type == "user") |
                    .message.content |
                    if type == "string" then .
                    elif type == "array" then (map(select(.type == "text") | .text) | first // "")
                    else "" end
                ' 2>/dev/null | head -1
            end
        )
        test -n "$display"; or set display $display_fallback
        test -n "$display"; or set display $short_id
        if test (string length -- "$display") -gt 60
            set display (string sub -l 57 -- "$display")"..."
        end

        printf '%s\t%s\t\033[1;33m%s\033[0m \033[1;32m|\033[0m %s\t%s\t%s\t%s\n' \
            "$jsonl" "$session_id" \
            "$short_id" "$display" \
            "$project" "$created" "$updated"
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
    set -l lines (opencode session list | string split '\n')
    if test (count $lines) -lt 3
        log_error "No sessions found!"
        return 1
    end

    set -l output (for line in $lines[3..-1]
        set -l sid (string match -r '^ses_[^[:space:]]+' -- "$line")
        if test -z "$sid"
            continue
        end

        set -l title_with_updated (string replace -r '^ses_[^[:space:]]+\s+' '' -- "$line")
        set -l title (string replace -r '\s+[0-9]{1,2}:[0-9]{2}\s+[AP]M(\s+·\s+[0-9]{1,2}/[0-9]{1,2}/[0-9]{4})?$' '' -- "$title_with_updated")

        printf '%s\t\033[1;33m%s\033[0m \033[1;32m|\033[0m %s\n' "$sid" "$sid" "$title"
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
