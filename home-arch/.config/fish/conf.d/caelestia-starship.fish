# Caelestia prompt for Arch terminals (overlay-owned, appearance only).
# The shared home/ fish config is never edited or shadowed here. conf.d
# snippets run BEFORE config.fish, so setting $STARSHIP_CONFIG here steers
# the shared `starship init fish | source` line to the overlay Caelestia
# prompt without touching shared starship.toml (Fedora keeps it).
# Interactive only and silent otherwise, so scripts and `fish -c` stay
# clean. No user-config sourcing: upstream `user-config.fish` stays
# unmanaged to avoid extra startup noise.
if status is-interactive
    set -l caelestia_starship "$HOME/.config/caelestia/starship-caelestia.toml"
    if test -f "$caelestia_starship"
        set -gx STARSHIP_CONFIG "$caelestia_starship"
    end
end
