# Fish completions for dot (this repo's CLI).
# Stowed to ~/.config/fish/completions/dot.fish; fish loads it automatically.

complete -c dot -f
complete -c dot -n __fish_use_subcommand -a init -d 'Full setup: helpers, packages, stow, plugins, shell'
complete -c dot -n __fish_use_subcommand -a stow -d 'Re-link home/ into $HOME'
complete -c dot -n __fish_use_subcommand -a doctor -d 'Verify helpers, packages, symlinks, shell'
complete -c dot -n __fish_use_subcommand -a check-packages -d 'List missing bundle packages'
complete -c dot -n __fish_use_subcommand -a package -d 'Add, remove, or list bundle packages'
complete -c dot -n __fish_use_subcommand -a update -d 'Pull, install, restow, sync plugins'
complete -c dot -n __fish_use_subcommand -a benchmark-shell -d 'Benchmark fish startup performance'
complete -c dot -n __fish_use_subcommand -a help -d 'Show help'
complete -c dot -n '__fish_seen_subcommand_from package' -a 'add remove list' -d 'Package action'
complete -c dot -n '__fish_seen_subcommand_from package; and __fish_seen_subcommand_from add' -l aur -s a -d 'Treat NAME as an AUR package'
complete -c dot -n '__fish_seen_subcommand_from benchmark-shell' -s r -l runs -r -d 'Number of runs (1-100)'
complete -c dot -n '__fish_seen_subcommand_from benchmark-shell' -s v -l verbose -d 'Show each run timing'
