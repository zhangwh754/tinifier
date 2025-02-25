#!/bin/sh
API_LIMIT="500"
api_key="../.tinify_api_key"

log_info() {
  printf "[\e[36m%s\e[0m] [\e[32mINFO\e[0m] $*" "$(date +'%H:%M:%S')"
}

log_warn() {
  printf "[\e[36m%s\e[0m] [\e[33mWARNING\e[0m] $*" "$(date +'%H:%M:%S')"
}

log_error() {
  printf "[\e[36m%s\e[0m] [\e[91mERROR\e[0m] $*" "$(date +'%H:%M:%S')"
}

check_tools() {
  tools="curl"
  for tool in $tools; do
    if [ ! "$(command -v "$tool")" ]; then
      log_error "\e[1m$tool\e[0m not found! Exiting....\n"
      exit 1
    fi
  done
}

clear_this_line(){
  printf '\r'
  cols="$(tput cols)"
  for _ in $(seq "$cols"); do
    printf ' '
  done
  printf '\r'
}

erase_lines(){
  test -z "$1" && lines="1" || lines="$1"
  [ "$lines" = 0 ] && return
  if [ "$lines" = 1 ]; then
    clear_this_line
  else
    lines=$((lines-1))
    clear_this_line
    for _ in $(seq "$lines"); do
      printf '\033[1A'
      clear_this_line
    done
  fi
}

process_image() {
  j=0
  while [ ! -f compressed/"$output_file" ]; do
    j="$((j + 1))"
    if [ "$j" -gt 1 ]; then
      log_info "Re-try $((j - 1))\n"
    fi
    if [ "$j" -gt 10 ]; then
      log_error "Too many re-tries! Exiting....\n"
      exit 1
    fi
    file="$(echo "$file" | cut -d '/' -f 2)"
    orig_size="$(($(stat --printf="%s" files/"$file") / 1024))"
    if [ "$orig_size" -gt 1024 ]; then
      orig_size_display="$(printf "%0.2f\n" "$(awk "BEGIN {print ($orig_size)/1024}")") MB"
    else
      orig_size_display="$orig_size KB"
    fi
    log_info "Compressing \"$file\".... (${orig_size_display}) ($count of $files_count)\n"
    curl --progress-bar --user api:"$api_key" --data-binary @files/"$file" --output api_response.txt -i https://api.tinify.com/shrink
    erase_lines 2
    if [ -f api_response.txt ]; then
      status_code=$(head <api_response.txt -1 | awk '{print $2}')
    else
      status_code="1"
    fi
    download_url="$(grep -i <api_response.txt Location | awk '{print $2}' | sed 's/\r//g')"
    if [ "$download_url" = "" ]; then
      log_warn "Something went wrong! Error code: $status_code Retrying....\n"
      if [ -f api_response.txt ]; then
        rm api_response.txt 2>/dev/null
      fi
      continue
    fi
    compression_count="$(grep -i <api_response.txt Compression-Count | awk '{print $2}' | sed 's/\r//g')"
    log_info "Total API Requests: $compression_count/$API_LIMIT\n"
    if [ "$compression_count" -gt "$((API_LIMIT - 1))" ]; then
      log_error "API Limit Reached! Exiting....\n"
      rm api_response.txt
      exit 1
    fi
    curl "$download_url" --progress-bar --user api:"$api_key" --header "Content-Type: application/json" --data '{ "preserve": ["location", "creation"] }' --output "compressed/$output_file"
    erase_lines 2
    new_size="$(stat --printf="%s" "compressed/$output_file")"
    if [ "$new_size" = "" ]; then
      new_size=1
    fi
    new_size="$((new_size / 1024))"
    if [ "$new_size" -gt 1024 ]; then
      new_size_display="$(printf "%0.2f\n" "$(awk "BEGIN {print ($new_size)/1024}")") MB"
    else
      new_size_display="$new_size KB"
    fi
    percentage="$(printf %.2f "$((10000 * new_size / orig_size))e-2")"
    log_info "Done compressing \"$file\" (${new_size_display}) (${percentage}%% of original)\n"
    rm api_response.txt
    echo ""
  done
}

check_tools

if [ -f "$api_key" ]; then
  api_key="$(cat $api_key)"
else
  log_error "API Key not found. Please save API key at \e[1m$api_key\e[0m"
  exit 1
fi

mkdir -p compressed
log_info "Starting compression....\n"
echo ""

{
  find files ! -name "$(printf "*\n*")" -name '*.JPG'
  find files ! -name "$(printf "*\n*")" -name '*.jpg'
  find files ! -name "$(printf "*\n*")" -name '*.JPEG'
  find files ! -name "$(printf "*\n*")" -name '*.jpeg'
  find files ! -name "$(printf "*\n*")" -name '*.PNG'
  find files ! -name "$(printf "*\n*")" -name '*.png'
} >tmp

files_count="$(wc <tmp -l 2>/dev/null)"
if [ "$files_count" -eq 0 ]; then
  log_error "No pictures found! Exiting....\n"
  exit 1
fi

count=0
output_counter=1  # Initialize the counter for output files

while IFS= read -r file; do
  count="$((count + 1))"
  output_file="img_$(printf "%02d" "$output_counter").${file##*.}"  # New file name with numbering and extension
  output_counter="$((output_counter + 1))"  # Increment counter
  process_image
done <tmp
rm tmp

if [ "$count" -eq 1 ]; then
  log_info "$count file compressed!\n"
else
  log_info "$count files compressed!\n"
fi

printf "Press enter to exit..."
read -r
