# Caelestia live scheme replay for Arch terminals (overlay-owned).
# The shared home/ fish config is never edited here: this snippet replays
# the active scheme's escape sequences at interactive starts, which is what
# themes Ghostty (its config deliberately carries no colours). Interactive
# only and silent otherwise, so scripts and `fish -c` stay clean; guarded
# so fish starts cleanly before the Caelestia installer has run and
# written its first sequences file.
if status is-interactive; and test -f "$HOME/.local/state/caelestia/sequences.txt"
    cat "$HOME/.local/state/caelestia/sequences.txt" 2>/dev/null; or true
end
