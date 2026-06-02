#!/bin/bash

RIG_SHELL_MARKER_START='# >>> rig managed >>>'
RIG_SHELL_MARKER_END='# <<< rig managed <<<'

rig_shell_managed_block_content() {
  local shell_name
  shell_name=${1:-bash}
  cat <<EOF
$RIG_SHELL_MARKER_START
# rig version-manager initialization (nvm, tenv, etc.)
export NVM_DIR="\${NVM_DIR:-\$HOME/.nvm}"
if [ -s "\$NVM_DIR/nvm.sh" ]; then
  . "\$NVM_DIR/nvm.sh"
fi
if command -v tenv >/dev/null 2>&1; then
  eval "\$(tenv hook $shell_name)"
fi
$RIG_SHELL_MARKER_END
EOF
}

rig_shell_profile_shell_name() {
  local profile_path
  profile_path=$1
  case "$profile_path" in
    *.zshrc|*.zprofile|*.zshenv)
      printf 'zsh\n'
      ;;
    *)
      printf 'bash\n'
      ;;
  esac
}

rig_shell_apply_managed_block() {
  local profile_path tmp_path line in_block replaced shell_name
  profile_path=$1
  if [ "$profile_path" = "" ]; then
    return 1
  fi
  if [ ! -f "$profile_path" ]; then
    : >"$profile_path" || return 1
  fi
  shell_name=$(rig_shell_profile_shell_name "$profile_path")
  tmp_path=$(mktemp "${profile_path}.rig.XXXXXX") || return 1
  in_block=no
  replaced=no
  while IFS= read -r line || [ "$line" != "" ]; do
    case "$line" in
      "$RIG_SHELL_MARKER_START"*)
        in_block=yes
        if [ "$replaced" = "no" ]; then
          rig_shell_managed_block_content "$shell_name" >>"$tmp_path" || {
            rm -f "$tmp_path"
            return 1
          }
          replaced=yes
        fi
        ;;
      "$RIG_SHELL_MARKER_END"*)
        in_block=no
        ;;
      *)
        if [ "$in_block" = "no" ]; then
          printf '%s\n' "$line" >>"$tmp_path"
        fi
        ;;
    esac
  done <"$profile_path"
  if [ "$replaced" = "no" ]; then
    rig_shell_managed_block_content "$shell_name" >>"$tmp_path" || {
      rm -f "$tmp_path"
      return 1
    }
  fi
  mv -f "$tmp_path" "$profile_path"
}
