# Functions for agentic session management using fzf.
# Pressing:
#   - ENTER will resume the selected session
#   - DELETE will delete the session
#   - ? will toggle the preview
function claude_session_list
    set -l sessions_dir ~/.claude/sessions

    if not test -d "$sessions_dir"
        log_error "No Claude sessions directory found!"
        return 1
    end

    set -l session_files "$sessions_dir"/*.json
    if test "$session_files" = "$sessions_dir/*.json"
        log_error "No sessions found!"
        return 1
    end
    set -l session_files (ls -t $session_files 2>/dev/null)

    set -l output (for session_file in $session_files
        set -l session_id (jq -r '.sessionId // ""' "$session_file" 2>/dev/null)
        if test -z "$session_id" -o "$session_id" = "null"
            continue
        end
        set -l name (jq -r '.name // .cwd // ""' "$session_file" 2>/dev/null)
        set -l short_id (string sub -l 8 "$session_id")
        printf '%s\t%s\t\033[1;33m%s\033[0m \033[1;32m|\033[0m %s\n' "$session_file" "$session_id" "$short_id" "$name"
    end | env SHELL=/bin/bash fzf --ansi --height=20 --delimiter='\t' --with-nth=3.. \
        --expect=delete \
        --bind '?:toggle-preview' \
        --preview '
            sf={1}
            sid=$(jq -r ".sessionId // \"-\"" "$sf" 2>/dev/null)
            cwd=$(jq -r ".cwd // \"-\"" "$sf" 2>/dev/null)
            name=$(jq -r ".name // \"-\"" "$sf" 2>/dev/null)
            sstat=$(jq -r ".status // \"-\"" "$sf" 2>/dev/null)
            s_ms=$(jq -r ".startedAt // 0" "$sf" 2>/dev/null)
            u_ms=$(jq -r ".updatedAt // 0" "$sf" 2>/dev/null)
            started=-; updated=-
            if [ "$s_ms" -gt 0 ] 2>/dev/null; then started=$(date -r $((s_ms / 1000)) "+%Y-%m-%d %H:%M:%S" 2>/dev/null); fi
            if [ "$u_ms" -gt 0 ] 2>/dev/null; then updated=$(date -r $((u_ms / 1000)) "+%Y-%m-%d %H:%M:%S" 2>/dev/null); fi
            enc_cwd=$(echo "$cwd" | tr "/" "-")
            jsonl="$HOME/.claude/projects/$enc_cwd/$sid.jsonl"
            desc=-
            if [ -f "$jsonl" ]; then
              desc=$(jq -r "select(.type == \"user\") | .message.content | if type == \"string\" then . elif type == \"array\" then (map(select(.type == \"text\") | .text) | first // \"-\") else \"-\" end" "$jsonl" 2>/dev/null | head -1 | head -c 200)
              [ -z "$desc" ] && desc=-
            fi
            printf "\033[1;33mID:\033[0m %s\n" "$sid"
            printf "\033[1;33mDirectory:\033[0m %s\n" "$cwd"
            printf "\033[1;33mCreated:\033[0m %s\n" "$started"
            printf "\033[1;33mUpdated:\033[0m %s\n\n" "$updated"
            printf "\033[1;34mName:\033[0m %s\n" "$name"
            printf "\033[1;34mStatus:\033[0m %s\n\n" "$sstat"
            printf "\033[1;32mDescription:\033[0m %s\n" "$desc"
        ' --preview-window=right:50%:hidden:wrap)

    if test (count $output) -lt 2
        return 0
    end

    set -l key $output[1]
    set -l session_file (echo "$output[2]" | cut -f1)
    set -l session_id (echo "$output[2]" | cut -f2)

    if test "$key" = delete -a -n "$session_file"
        set -l cwd (jq -r '.cwd // ""' "$session_file" 2>/dev/null)
        set -l encoded_cwd (string replace -a '/' '-' "$cwd")
        rm -f "$session_file"
        if test -n "$session_id" -a -n "$encoded_cwd"
            rm -rf "$HOME/.claude/projects/$encoded_cwd/$session_id"
            rm -f "$HOME/.claude/projects/$encoded_cwd/$session_id.jsonl"
        end
        return 0
    end

    if test -n "$session_id"
        claude -r "$session_id"
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
