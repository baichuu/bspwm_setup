# Minimal prompt-only Zsh configuration.
autoload -Uz colors add-zsh-hook
colors
setopt PROMPT_SUBST

zmodload zsh/datetime
typeset -gF PROMPT_COMMAND_STARTED_AT=0
typeset -g PROMPT_COMMAND_DURATION_SEGMENT=''

prompt_timer_preexec() {
  PROMPT_COMMAND_STARTED_AT=$EPOCHREALTIME
}

prompt_timer_precmd() {
  ((PROMPT_COMMAND_STARTED_AT > 0)) || return

  local -F elapsed=$((EPOCHREALTIME - PROMPT_COMMAND_STARTED_AT))
  local duration
  if ((elapsed < 1)); then
    printf -v duration '%.0fms' $((elapsed * 1000))
  elif ((elapsed < 60)); then
    printf -v duration '%.2fs' $elapsed
  else
    local -i minutes=$((elapsed / 60))
    printf -v duration '%dm %.1fs' $minutes $((elapsed - minutes * 60))
  fi

  PROMPT_COMMAND_DURATION_SEGMENT="%F{8}${duration}%f"
  PROMPT_COMMAND_STARTED_AT=0
}

add-zsh-hook preexec prompt_timer_preexec
add-zsh-hook precmd prompt_timer_precmd

PS1='%F{red} %F{blue}${PWD/#$HOME/~}%F{red}   %f'
RPROMPT='$PROMPT_COMMAND_DURATION_SEGMENT'
