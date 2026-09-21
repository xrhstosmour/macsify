# Live tab naming hook for the `herdr-automatic-rename` plugin, installed by
# `setup/agentic.sh`. Fish glob expansion is nullglob by default, so a
# no-match before install expands to nothing instead of erroring.
# conf.d files source into the global scope, not a function's, so a bare
# `for` loop var here would leak into every session, hence the `set -e`.
for _f in $HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.fish
    test -r "$_f"; and source "$_f"; and break
end
set -e _f
