# Caelestia live scheme replay for Arch terminals (overlay-owned).
# The shared home/ fish config is never edited here: this snippet runs at
# every interactive start and replays the active scheme's escape sequences,
# which is what themes Ghostty (its config deliberately carries no colours).
# Guarded so fish starts cleanly before the Caelestia installer has run and
# written its first sequences file.
if test -f "$HOME/.local/state/caelestia/sequences.txt"
    cat "$HOME/.local/state/caelestia/sequences.txt"
end
