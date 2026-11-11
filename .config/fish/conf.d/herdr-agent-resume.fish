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
    commandline -f execute
end

# An agent started by hand and ended by the person is not to come back.
function __herdr_agent_resume_forget --on-event fish_postexec
    string match -rq '^(claude|opencode)(\s|$)' -- $argv[1]; or return
    bash ~/.config/agentic/hooks/herdr-application-resume.sh forget
end
