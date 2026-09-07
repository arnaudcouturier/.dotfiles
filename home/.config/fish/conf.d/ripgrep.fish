# Let ripgrep pick up home/.config/ripgrep/config (--hidden, size cap).
# Guarded so fish starts cleanly before the first `dot stow` populates it.
if test -f "$HOME/.config/ripgrep/config"
    set -gx RIPGREP_CONFIG_PATH "$HOME/.config/ripgrep/config"
end
