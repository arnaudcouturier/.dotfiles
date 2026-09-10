# Caelestia greeting for Arch terminals (overlay-owned, additive only).
# Upstream source: caelestia-dots/caelestia @ 1ee7a98
# fish/functions/fish_greeting.fish (Caelestia ASCII in colour 16 plus
# `fastfetch --key-padding-left 5`). This conf.d definition overrides the
# shared autoloaded fish_greeting on Arch only (the overlay never stows on
# Fedora, so Fedora keeps its suppressed greeting). No shared file is
# shadowed, so the existing collision set stays exactly Ghostty.
# fish_greeting runs only for interactive shells by design; the fastfetch
# call is guarded so a missing binary stays silent. The boxed layout comes
# from the overlay fastfetch-boxed.jsonc via an explicit --config, so direct
# `fastfetch` calls still use the shared config untouched.
function fish_greeting
    echo -ne '\x1b[38;5;16m'
    echo '     ______           __          __  _       '
    echo '    / ____/___ ____  / /__  _____/ /_(_)___ _ '
    echo '   / /   / __ `/ _ \/ / _ \/ ___/ __/ / __ `/ '
    echo '  / /___/ /_/ /  __/ /  __(__  ) /_/ / /_/ /  '
    echo '  \____/\__,_/\___/_/\___/____/\__/_/\__,_/   '
    set_color normal
    if type -q fastfetch
        set -l boxed "$HOME/.config/caelestia/fastfetch-boxed.jsonc"
        if test -f "$boxed"
            fastfetch --config "$boxed" --key-padding-left 5 2>/dev/null; or true
        else
            fastfetch --key-padding-left 5 2>/dev/null; or true
        end
    end
end
