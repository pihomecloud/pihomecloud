#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls -h --color=auto'
PS1='[\u@\h \W]\$ '
alias ll='ls -l'
alias vi='vim'
export PS1="\[\e[01;32m\]\u\[\e[0m\]\[\e[01;37m\]@\[\e[0m\]\[\e[01;31m\]\h\[\e[0m\]\[\e[00;37m\] [\[\e[0m\]\[\e[01;34m\]\w\[\e[0m\]\[\e[00;37m\]]\\$\[\e[0m\] "
export EDITOR='vim'

