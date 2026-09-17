# Starship prompt init. Guarded so machines without the binary keep stock
# fish; Arch Caelestia overrides STARSHIP_CONFIG in its own conf.d drop-in.
if type -q starship
    starship init fish | source
end
