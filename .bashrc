# all screen shells are non-logins shells
shopt -s histappend
shopt -s cmdhist
HISTTIMEFORMAT='%F %T '
TERM=xterm-256color
set -o vi
export PATH=$HOME/bin/:$PATH
alias vi="vim"
alias expl="run explorer.exe `cygpath.exe -w $PWD`"
alias apt-cygports="apt-cyg -m ftp://sourceware.org/pub/cygwinports/"
alias tcpdump="windump -l"
alias inet="/usr/sbin/inetd.exe -D -d"
alias mident="mplayer -vo null -ao null -frames 0 -identify "
alias bgname='reg query "HKCU\Software\Microsoft\Internet Explorer\Desktop\General" /v WallpaperSource | awk -F\\ "/REG_SZ/ {print $NF}"'

# Set the title of a Terminal window
function settitle() {
 if [ -n "$STY" ] ; then         # We are in a screen session
  echo "Setting screen titles to $@"
  printf "\033k%s\033\\" "$@"
  screen -X eval "at \\# title $@" "shelltitle $@"
 else
  printf "\033]0;%s\007" "$@"
 fi
}

#function ssh() {
#	settitle "$1"
#	/usr/bin/ssh $*
#}

#stty lnext ^q stop undef start undef

export PS1="\[\033]0;\u@\h:\w\007\]#<\u@\h:\w>\n;"
#export PS1="\[\033]0;${USER}@${HOSTNAME}\007\]"  ##display user@host in titlebar or "%h" screen string escape
#export PS1=${PS1}'\[\033k\033\\\]'  ##display running command for window name in screen's caption line
#export PS1=${PS1}'\[\033k'${HOSTNAME}'\033\\\]'  ##show hostname for window name on screen's caption line when idle
#export PS1='#<\u@\h:\w>\n'${PS1}'\n; '
