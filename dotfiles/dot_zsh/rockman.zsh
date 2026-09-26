# -*- mode: shell-script -*-
# -*- coding: utf-8 -*-

# Each character in a sprite row names one pixel. A dot is transparent.
typeset -gA ROCKMAN_PALETTE=(
  K 16
  B 27
  C 81
  S 223
  W 231
)

typeset -ga ROCKMAN_SPRITE=(
  '......KKKKKKKK......'
  '....KKBBCCCCBBKK....'
  '...KBBBBCCCCBBBBK...'
  '..KBBBBBCCCCBBBBBK..'
  '..KBBBBBCCCCBBBBBK..'
  '.KBBBBBBBBBBBBBBBBK.'
  '.KBBBKKKKKKKKKKBBBK.'
  'KCCBKSSSSSSSSSSKBCCK'
  'KCCBKSWWKSSKWWSKBCCK'
  'KCCBKSWWKSSKWWSKBCCK'
  'KCCBKSWWKSSKWWSKBCCK'
  '.KBBKSSSSSSSSSSKBBK.'
  '.KBBBKSSSKKSSSKBBBK.'
  '..KKKKKSSSSSSKKKKK..'
  '...KBBKKKKKKKKBBK...'
  '..KCCKCCCCCCCCKCCK..'
  '.KCCCKCCCCCCCCKCCCK.'
  '.KCCKKCCCCCCCCKKCCK.'
  '.KBBBKCCCCCCCCKBBBK.'
  '.KBBBKBBBBBBBBKBBBK.'
  '..KKKKBBBBBBBBKKKK..'
  '....KCCCKKKKCCCK....'
  '...KBBBBK..KBBBBK...'
  '..KBBBBBK..KBBBBBK..'
  '.KBBBBBBK..KBBBBBBK.'
  '.KKKKKKKK..KKKKKKKK.'
)

# Prints one terminal cell that shows two vertically stacked pixels.
# The 256-color palette keeps the colors intact inside tmux, which drops
# 24-bit colors unless its terminal-overrides enable them.
function print-rockman-cell() {
  local upper_pixel=$1
  local lower_pixel=$2
  local upper_color=${ROCKMAN_PALETTE[$upper_pixel]}
  local lower_color=${ROCKMAN_PALETTE[$lower_pixel]}
  if [[ -z $upper_color && -z $lower_color ]]; then
    printf '\e[0m '
  elif [[ -z $lower_color ]]; then
    printf '\e[0;38;5;%sm▀' "$upper_color"
  elif [[ -z $upper_color ]]; then
    printf '\e[0;38;5;%sm▄' "$lower_color"
  else
    printf '\e[0;38;5;%s;48;5;%sm▀' "$upper_color" "$lower_color"
  fi
}

# Prints a pixel-art Rockman, packing two sprite rows into each line.
function print-rockman() {
  local row_index column_index upper_row lower_row
  for (( row_index = 1; row_index <= ${#ROCKMAN_SPRITE}; row_index += 2 )); do
    upper_row=${ROCKMAN_SPRITE[row_index]}
    lower_row=${ROCKMAN_SPRITE[row_index + 1]}
    for (( column_index = 1; column_index <= ${#upper_row}; column_index++ )); do
      print-rockman-cell "${upper_row[column_index]}" "${lower_row[column_index]}"
    done
    printf '\e[0m\n'
  done
}
