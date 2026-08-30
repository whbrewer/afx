# afx-aliases.sh -- xmarks-style single-letter shortcuts for afx.
# Source after afx.sh:
#   source ~/.local/bin/afx.sh
#   source ~/.local/bin/afx-aliases.sh
#
# Each alias just expands to the two-word afx subcommand, so it inherits
# whichever `afx` is in scope: the sourced shell function (needed for `xg`
# to cd in your actual shell) if afx.sh is sourced first, or the `afx`
# binary otherwise. See DESIGN.md's xmarks/afx verb table for why these
# particular letters.
alias xs='afx star'
alias xg='afx go'
alias xl='afx list'
alias xq='afx status'
alias xd='afx rm'
alias xf='afx find'
alias xj='afx jobs'
alias xp='afx push'
alias xr='afx pull'
