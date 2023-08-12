tell application "Sublime Text"
  activate
end tell

set screen_res to do shell script "system_profiler SPDisplaysDataType | awk '/Resolution/{print $2, $3, $4}'"
set screen_list to words of screen_res
set width to item 1 of screen_list as number
set height to item 3 of screen_list as number

-- if width < height then
if height > 2000 then
  tell application "System Events" to keystroke "2" using {command down, option down, shift down}
else
  tell application "System Events" to keystroke "2" using {command down, option down}
end if
tell application "System Events" to keystroke "2" using control down

do shell script "EDITOR=/usr/local/bin/subl ~/chat/run --new-file"
