# Fish calls this only for interactive shells. Keep scripts quiet.
function fish_greeting
    if type -q fastfetch
        fastfetch
    end
end
