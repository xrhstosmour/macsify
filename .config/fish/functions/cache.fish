# Function to source a tool's init script from a cache instead of spawning the tool on every
# new terminal, about 40 ms each. The cache is rebuilt when the tool's binary is
# newer than it, which covers an upgrade, and each distinct command has its own file.
# Usage:
#   _source_cached_init starship init fish --print-full-init
function _source_cached_init --description "Source a tool's init script from a cache, rebuilt when the tool's binary is newer."
    set -l binary (command -v $argv[1])
    or return

    set -l cache_directory $HOME/.cache/fish/init
    set -l cache_file $cache_directory/(string join -- _ $argv | string replace -a -r '[^A-Za-z0-9]' _).fish

    if not test -s $cache_file; or test $binary -nt $cache_file
        mkdir -p $cache_directory
        if $argv >$cache_file.partial
            mv $cache_file.partial $cache_file
        else
            rm -f $cache_file.partial
            return
        end
    end

    source $cache_file
end
