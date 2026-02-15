# -*- mode: shell-script -*-
# -*- coding: utf-8 -*-
# Development tools functions

# ROS catkin functions
function catkin-compile-commands-json() {
  local catkin_ws=$(echo $CMAKE_PREFIX_PATH | cut -d: -f1)/..
  # Verify catkin cmake args contains -DCMAKE_EXPORT_COMPILE_COMMANDS=ON.
  # If the arguments does not include the option, add to cmake args.
  (cd "${catkin_ws}" && catkin config | grep -- -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null)
  local catkin_config_contains_compile_commands=$?
  if [ $catkin_config_contains_compile_commands -ne 0 ]; then
    echo catkin config does not include -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    (
      cd "${catkin_ws}" &&
        catkin config -a --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    )
  fi
  # Run catkin build in order to run cmake and generate compile_commands.json
  (cd "${catkin_ws}" && catkin build)
  # Find compile_commands.json in build directory and create symlink to the top of the package
  # directories.
  local package_directories=$(find "${catkin_ws}/src" -name package.xml | xargs -n 1 dirname)
  for package_dir in $package_directories; do
    local package=$(echo $package_dir | xargs -n 1 basename)
    (
      cd "${catkin_ws}" || return
      if [ -e ${catkin_ws}/build/$package/compile_commands.json ]; then
        ln -sf ${catkin_ws}/build/$package/compile_commands.json \
           $(rospack find $package)/compile_commands.json
      fi
    )
  done
}

# Wrapper of catkin_test_results
function catkin-test-results() {
  local target_dir=$(realpath ${1:-.})
  if [ ${target_dir} = "/" ]; then
    :
  elif [ -e ${target_dir}/package.xml ]; then
    local pkg_name=$(basename $(readlink -f ${target_dir}))
    local catkin_ws=$(echo ${CMAKE_PREFIX_PATH} | cut -d: -f1)/..
    catkin_test_results --verbose ${catkin_ws}/build/${pkg_name}
  else
    catkin-test-results ${target_dir}/..
  fi
}

function roscode() {
  (roscd $1 && code .)
}

compctl -K "_roscomplete" "roscode"

# PDF translation utilities using pdf2zh
# pdf2zh is a command to translate a pdf into another language.
pdf2ja-gemini(){
  if ! command -v pdf2zh &> /dev/null; then
    echo "Error: pdf2zh is not installed. Please install pdf2zh using: uv tool install pdf2zh --python 3.12"
    return 1
  fi

  local vault="Private"
  if op vault get "Employee" &>/dev/null; then
    vault="Employee"
  fi

  GEMINI_API_KEY="$(op read "op://${vault}/generativelanguage.googleapis.com/apikey")" \
                pdf2zh -lo ja -li en -s gemini:gemini-3-flash-preview "$1"
}

pdf2ja-gemma3(){
  local OLLAMA_MODEL="gemma3:4b"

  if ! command -v pdf2zh &> /dev/null; then
    echo "Error: pdf2zh is not installed. Please install pdf2zh using: uv tool install pdf2zh --python 3.12"
    return 1
  fi

  if ! command -v ollama &> /dev/null; then
    echo "Error: ollama is not installed. Please install ollama from ollama.com"
    return 1
  fi

  # Check if ollama is running
  if ! ollama ps &> /dev/null; then
    echo "Error: ollama server is not running. Please start ollama."
    echo "You can typically start it by running 'ollama serve' in a separate terminal or ensuring the desktop app is running."
    return 1
  fi

  # Check if $OLLAMA_MODEL is available in ollama
  if ! ollama list | grep -q "$OLLAMA_MODEL"; then
    echo "Error: Model '$OLLAMA_MODEL' is not available in ollama."
    echo "Please download it using: ollama pull $OLLAMA_MODEL"
    return 1
  fi

  pdf2zh -lo ja -li en -s ollama:"$OLLAMA_MODEL" "$1"
}

function llm-gemini() {
  local vault="Private"
  if op vault get "Employee" &>/dev/null; then
    vault="Employee"
  fi

  echo $@ | GEMINI_API_KEY="$(op read "op://${vault}/generativelanguage.googleapis.com/apikey")" \
                llm -m "gemini-3-flash-preview" -s "Answer in Japanese briefly"
}

function llm-local() {
  echo $@ | llm -m "gemma3:4b" -s "Answer in Japanese briefly"
}

# A function to convert a movie file to a mp3 file.
# We use 48kbps for the bit rate.
function ffmpeg-mp3-convert() {
  local target_file="$1"
  local output_file="${target_file%.*}.mp3"
  ffmpeg -i "${target_file}" -b:a 48k "${output_file}"
}

function gemini-docker() {
  local docker_args=(
    -it --rm
    -v "${PWD}:${PWD}"
    -w "${PWD}"
    -u "$(id -u):$(id -g)"
    -v "/etc/passwd:/etc/passwd:ro"
    -v "/etc/group:/etc/group:ro"
    -e "GEMINI_API_KEY=${GEMINI_API_KEY}"
    -e "HOME=/home/gemini"
  )

  # Mount gcloud config
  if [ -d "$HOME/.config/gcloud" ]; then
    docker_args+=(-v "$HOME/.config/gcloud:/home/gemini/.config/gcloud")
  fi

  # Mount gemini config
  if [ -d "$HOME/.config/gemini" ]; then
    docker_args+=(-v "$HOME/.config/gemini:/home/gemini/.config/gemini")
  fi

  # Mount .gemini directory
  if [ -d "$HOME/.gemini" ]; then
    docker_args+=(-v "$HOME/.gemini:/home/gemini/.gemini")
  fi

  # Mount Application Default Credentials
  if [ -d "$HOME/.config/google-cloud-sdk" ]; then
    docker_args+=(-v "$HOME/.config/google-cloud-sdk:/home/gemini/.config/google-cloud-sdk")
  fi

  docker run "${docker_args[@]}" \
    "us-docker.pkg.dev/gemini-code-dev/gemini-cli/sandbox:$(gemini --version)" \
    gemini "$@"
}
