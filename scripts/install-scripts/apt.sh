APT_PACKAGES="ttyrec git-core emacs vim tmux anthy-el ssh zsh curl htop atom \
toilet ffmpeg jq"
runsudo add-apt-repository -y ppa:webupd8team/atom # for atom
runsudo add-apt-repository -y ppa:jon-severinsson/ffmpeg
runsudo apt-get update
runsudo apt-get install aptitude
runsudo aptitude upgrade
runsudo aptitude install $APT_PACKAGES
