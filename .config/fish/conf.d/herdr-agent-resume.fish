# Brings back the coding agent a `Herdr` app terminal lost to a reboot. The
# terminal's shell and folder survive, the agent inside does not, so a hook
# recorded its session (`.config/agentic/hooks/herdr-application-resume.sh`) and
# the first prompt of the terminal's own shell resumes it. The record is
# forgotten when the agent returns, so one that is still there at shell start
# means the agent never exited by itself. It stays during the resume, `OpenCode`
# saves a session only on its next chat message, so a second reboot before one
# would lose it.
status is-interactive; or return
set -q HC_TERMINAL_ID; or return
command -q jq; or return
test -f ~/.config/agentic/hooks/herdr-application-resume.sh; or return

function __herdr_agent_resume --on-event fish_prompt
    functions -e __herdr_agent_resume

    set -l line (bash ~/.config/agentic/hooks/herdr-application-resume.sh show $fish_pid); or return
    test -n "$line"; or return
    set -l fields (string split \t -- $line)
    test (count $fields) -ge 3; or return
    set -l flags $fields[4..-1]

    set -l agent
    switch $fields[1]
        case claude
            set agent claude --resume $fields[2] $flags
        case opencode
            set agent opencode --session $fields[2] $flags
    end
    if test -z "$agent"; or not command -q $agent[1]
        bash ~/.config/agentic/hooks/herdr-application-resume.sh forget
        return
    end

    echo "Resuming $fields[1] session $fields[2]."
    cd $fields[3]; or return
    # Run from the command line, not from this handler, fish gives a command an
    # event handler runs no process group of its own, so the terminal's
    # foreground program stays `fish` and `Herdr` sees no agent. The
    # `fish_postexec` handler below forgets the record once it exits.
    commandline -r -- (string join ' ' -- (string escape -- $agent))
    # This prompt must not query the terminal, the agent would start before the
    # reply and swallow it, and the still pending query panics `fish` at the next
    # prompt. The variable is an undocumented test hook of `Reader::query`, so a
    # `fish` it is not verified on gets the command typed in for Enter instead,
    # the reply then lands before the agent starts.
    if __herdr_agent_resume_can_skip_query
        set -g FISH_TEST_NO_RECURRENT_QUERIES 1
        commandline -f execute
    else
        echo "Press Enter to resume it."
    end
end

# Verified on `fish` 4.9.3, re-check `Reader::query` in `src/reader/reader.rs`
# before widening it to a new major version.
function __herdr_agent_resume_can_skip_query
    string match -q '4.*' -- $version
end

# An agent started by hand and ended by the person is not to come back.
function __herdr_agent_resume_forget --on-event fish_postexec
    string match -rq '^(claude|opencode)(\s|$)' -- $argv[1]; or return
    set -e FISH_TEST_NO_RECURRENT_QUERIES
    bash ~/.config/agentic/hooks/herdr-application-resume.sh forget
end
