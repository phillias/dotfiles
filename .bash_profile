# used for login shells, like rxvt, bash shell, etc.

screen -wipe

# however all screen logins are non-login, so everything is stored in .bashrc
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
