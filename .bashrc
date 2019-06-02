### Add git branch if its present to PS1
color_prompt=yes
force_color_prompt=yes

export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWCOLORHINTS=1
export GIT_PS1_SHOWUNTRACKEDFILES=1

BLACK="\[$(tput setaf 240)\]"
PURPLE="\[$(tput setaf 125)\]"
RED="\[$(tput setaf 1)\]"
GREEN="\[$(tput setaf 2)\]"
YELLOW="\[$(tput setaf 3)\]"
BLUE="\[$(tput setaf 4)\]"
RESET="\[$(tput sgr0)\]"

export PROMPT_COMMAND='__git_ps1 "${BLUE}\u${PURPLE}@${YELLOW}\h${BLACK}:${RED}\w${RESET}" "${GREEN}\n\\\$${YELLOW}> ${RESET}"'

### Known hosts completion for ssh / ping
# _complete_ssh_hosts ()
# {
#         COMPREPLY=()
#         cur="${COMP_WORDS[COMP_CWORD]}"
#         comp_ssh_hosts=`cat ~/.ssh/known_hosts | grep -v ^# | cut -f 1 -d ' ' \
#                         | sed -e s/,.*//g | sed -e s/\].*//g | sed -e s/\\\[//g | uniq`
#         COMPREPLY=( $(compgen -W "${comp_ssh_hosts}" -- $cur))
#         return 0
# }

# complete -F _complete_ssh_hosts ssh
# complete -F _complete_ssh_hosts ping

### TMUX
if [[ -z "$TMUX" ]] ;then
    ID="`tmux ls | grep -vm1 attached | cut -d: -f1`" # get the id of a deattached session
    if [[ -z "$ID" ]] ;then # if not available create a new one
        tmux new-session
    else
        tmux attach-session -t "$ID" # if available attach to it
    fi
fi

### KUBECTL AUTOCOMPLETE
# source <(kubectl completion bash) # setup autocomplete in bash, bash-completion package should be installed first.

### SSH TMUX RENAME
# ssh() {
#     tmux rename-window "$*"
#     command ssh "$@"
#     tmux rename-window "bash"
# }

getAWSTokenRemainingMinutes() {
	aws_token_remaining=$(($AWS_EXPIRY - `date +%s`))
	aws_token_remaining_minutes=$(($aws_token_remaining/60))
	echo $aws_token_remaining_minutes
}
alias dps="docker ps -q | xargs docker inspect --format='{{ .Name }} - {{range .NetworkSettings.Networks}}{{println .IPAddress}}{{end}}'"

# xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/handle-brightness-keys
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/handle-brightness-keys --create -t bool -s true

# xinput --list
sudo xinput --set-prop 'Microsoft Microsoft 3-Button Mouse with IntelliEye(TM)' 'libinput Accel Profile Enabled' 0, 1


