# -*- mode: shell-script -*-
# -*- coding: utf-8 -*-

# Each character in a sprite row names one pixel. A dot is transparent.
# The colors are the NES PPU palette entries that the sprite uses.
typeset -gA ROCKMAN_PALETTE=(
  [K]='0;0;0'
  [B]='0;112;236'
  [C]='0;232;216'
  [S]='252;228;160'
  [W]='252;252;252'
)

# The idle frame of Rockman (NES, 1987), mirrored to face right as the game
# does at the start of a stage. Source sheet ripped by Mister Mike:
# https://www.spriters-resource.com/nes/mm/asset/144772/
typeset -ga ROCKMAN_SPRITE=(
  '..........KKK........'
  '........KKKCCK.......'
  '.......KBBBKCCK......'
  '......KBBBBBKKKK.....'
  '......KBBBBBKCCBK....'
  '.....KCBBBBBBKKBK....'
  '.....KCBBSWWWBBWK....'
  '.....KCBSWWKKSKWK....'
  '......KBSWWKKSKWK....'
  '.....KKBSSWWWSWSK....'
  '...KKCCKBSKKKKSKKK...'
  '..KBCCCCKSSSSSKCCBK..'
  '..KBBCCCCKKKKKCCBBK..'
  '.KBBBCKCCCCCCCKCBBBK.'
  '.KBBKKKCCCCCCCKKKBBK.'
  '.KBBBKKCCCCCCCKKBBBK.'
  '.KBBBKKBBBBBBBKKBBBK.'
  '..KKK.KBBBBBBBK.KKK..'
  '.....KCCBBBBCCCK.....'
  '....KBBCCCKCCCCBK....'
  '...KKBBBCK.KCBBBKK...'
  '.KKBBBBBK...KBBBBBKK.'
  'KBBBBBBBK...KBBBBBBBK'
  'KKKKKKKKK...KKKKKKKKK'
)

# Prints one terminal cell that shows two vertically stacked pixels.
# A tmux without the RGB feature maps the 24-bit colors to its 256 colors.
function print-rockman-cell() {
  local upper_pixel=$1
  local lower_pixel=$2
  local upper_color=${ROCKMAN_PALETTE[$upper_pixel]}
  local lower_color=${ROCKMAN_PALETTE[$lower_pixel]}
  if [[ -z $upper_color && -z $lower_color ]]; then
    printf '\e[0m '
  elif [[ -z $lower_color ]]; then
    printf '\e[0;38;2;%sm▀' "$upper_color"
  elif [[ -z $upper_color ]]; then
    printf '\e[0;38;2;%sm▄' "$lower_color"
  else
    printf '\e[0;38;2;%s;48;2;%sm▀' "$upper_color" "$lower_color"
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
