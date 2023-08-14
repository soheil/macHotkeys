#!/bin/bash

EDITOR_APP_NAME="Sublime Text"

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

osascript -e "quit app \"$EDITOR_APP_NAME\""

while IFS= read -r line; do
  launchctl setenv "${line%=*}" "${line#*=}"
done < ~/.env


open -a "$EDITOR_APP_NAME"

$DIR/chat0/heater &
$DIR/mic &

while true; do
  sleep 100
done
