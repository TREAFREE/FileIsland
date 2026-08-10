on run argv
    set mountPath to item 1 of argv
    tell application "Finder"
        set targetFolder to POSIX file mountPath as alias
        set backgroundFile to POSIX file (mountPath & "/.background/background.png") as alias
        open targetFolder
        set targetWindow to container window of targetFolder
        set current view of targetWindow to icon view
        set toolbar visible of targetWindow to false
        set statusbar visible of targetWindow to false
        set bounds of targetWindow to {120, 120, 780, 540}
        set theViewOptions to the icon view options of targetWindow
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 112
        set text size of theViewOptions to 14
        set background picture of theViewOptions to backgroundFile
        set position of item "File Island.app" of targetFolder to {165, 215}
        set position of item "Applications" of targetFolder to {495, 215}
        update targetFolder without registering applications
        delay 2
        close targetWindow
        delay 2
    end tell
end run
