#!/bin/bash

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


process_id=$(ps aux | grep '[M]acOS/Sublime Text' | awk '{print $2}')
kill $process_id
while ps -p $process_id > /dev/null; do sleep 1; done

while IFS= read -r line; do
  launchctl setenv "${line%=*}" "${line#*=}"
done < $DIR/.env


open -a "Sublime Text"

$DIR/chat0/heater &
$DIR/macHotkeys/mic &

while true; do
  sleep 100
done
