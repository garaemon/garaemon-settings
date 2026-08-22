# -*- mode: shell-script -*-
# -*- coding: utf-8 -*-
# Aliases

# alias cp='cp -v'
alias mv='mv -v'
alias grep='grep --color=auto'
alias wifi-diag="open '/System/Library/CoreServices/Wi-Fi Diagnostics.app'"
alias rqt_reconfigure="rosrun rqt_reconfigure rqt_reconfigure"
alias docker-bash="sudo docker run -i -t ubuntu:12.04 /bin/bash"
alias v="view"
alias s="source ~/.zshrc"
alias git-graph="git log --graph --decorate --oneline"
alias git-twodiff="git difftool -y -x \"colordiff -y -W $COLUMNS\" | less -R"
alias c=code
alias gemini-flash="gemini -m gemini-3-flash-preview"
