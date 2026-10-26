-- TVX - intenta iniciar la descarga de Canva usando accesibilidad.
-- Uso:
--   osascript TVX_Canva_Download.applescript download [proceso]
--   osascript TVX_Canva_Download.applescript inspect [proceso]
-- El proceso por defecto es "Canva"; también puede ser "Safari".
-- Devuelve: CLICKED, MANUAL, NO_CANVA, NO_WINDOW, NO_PERMISSION,
--           DIALOG_FAILED, NO_BUTTON o el listado de inspect.

property targetProcess : "Canva"

on run argv
    set mode to "download"
    if (count of argv) > 0 then set mode to item 1 of argv
    if (count of argv) > 1 then set targetProcess to item 2 of argv

    try
        tell application "System Events"
            if not (exists process targetProcess) then return "NO_CANVA"
        end tell
    on error errMsg number errNum
        return "NO_PERMISSION: " & errNum & " " & errMsg
    end try

    try
        tell application "System Events"
            tell process targetProcess
                set frontmost to true
                if (count of windows) is 0 then return "NO_WINDOW"
            end tell
        end tell
    on error errMsg number errNum
        return "NO_PERMISSION: " & errNum & " " & errMsg
    end try

    if mode is "inspect" then return my inspectCanva()

    -- 1) Flujo real de Canva: Compartir -> Descargar.
    set shared to my clickTopRight({"Compartir", "Share"}, "window")
    if shared is not "CLICKED" then return "MANUAL"
    delay 2

    -- En el diálogo de Compartir hay "Descargar" y "Descargar la selección".
    -- Pulsamos el primero, excluyendo el de selección.
    set clicked to "NO"
    set candidates to my findElements({"Descargar", "Download"}, "dialog")
    repeat with e in candidates
        set l to my elementLabel(e)
        ignoring case
            if (l contains "Descargar" or l contains "Download") and l does not contain "selección" and l does not contain "seleccion" and l does not contain "selection" then
                if my pressElement(e) then
                    set clicked to "CLICKED"
                    exit repeat
                end if
            end if
        end ignoring
    end repeat
    if clicked is not "CLICKED" then return "MANUAL"
    delay 2

    -- 2) Diálogo de descarga. Si ya está Video MP4, no tocar el selector.
    try
        set mp4s to my findElements({"Video MP4"}, "dialog")
        if (count of mp4s) is 0 then
            set fmt to my findElements({"JPG", "PNG", "PDF", "GIF"}, "dialog")
            if (count of fmt) > 0 then
                my pressElement(item 1 of fmt)
                delay 1
                set mp4s to my findElements({"Video MP4"}, "dialog")
                if (count of mp4s) > 0 then my pressElement(item 1 of mp4s)
            end if
        end if
    end try

    try
        set hd to my findElements({"1080", "Full HD"}, "dialog")
        if (count of hd) > 0 then my pressElement(item 1 of hd)
    end try

    try
        set allp to my findElements({"Todo", "Todas las páginas", "All pages", "Todas"}, "dialog")
        if (count of allp) > 0 then my pressElement(item 1 of allp)
    end try

    delay 1

    -- 3) Botón final Descargar dentro del diálogo. Si hay varios, el más bajo.
    set buttons to my findElements({"Descargar", "Download"}, "dialog")
    if (count of buttons) is 0 then return "DIALOG_FAILED"
    set best to missing value
    set bestY to -1
    repeat with e in buttons
        try
            set p to my positionOf(e)
            if p is not missing value then
                set y to item 2 of p
                if y > bestY then
                    set best to e
                    set bestY to y
                end if
            end if
        end try
    end repeat
    if best is missing value then set best to item -1 of buttons
    if my pressElement(best) then return "CLICKED"
    return "DIALOG_FAILED"
end run

on rootFor(whichArea)
    tell application "System Events"
        tell process targetProcess
            if whichArea is "dialog" then
                try
                    if (count of sheets of window 1) > 0 then return sheet 1 of window 1
                end try
                try
                    return front window
                end try
            else
                try
                    return window 1
                end try
            end if
        end tell
    end tell
    return missing value
end rootFor

on roleOf(e)
    try
        tell application "System Events" to return role of e as text
    end try
    return ""
end roleOf

on valueOf(e)
    try
        tell application "System Events" to return value of e
    end try
    return ""
end valueOf

on positionOf(e)
    try
        tell application "System Events" to return position of e
    end try
    return missing value
end positionOf

on roleIs(e, roles)
    set r to my roleOf(e)
    repeat with x in roles
        if r is (x as text) then return true
    end repeat
    return false
end roleIs

on elementLabel(e)
    set parts to {}
    tell application "System Events"
        try
            set end of parts to (name of e as text)
        end try
        try
            set end of parts to (description of e as text)
        end try
        try
            set end of parts to (title of e as text)
        end try
        try
            set end of parts to (help of e as text)
        end try
    end tell
    return parts as text
end elementLabel

on walk(e, depth, maxDepth, keywords)
    global gFound, gNodes
    if gNodes > 20000 then return
    if depth > maxDepth then return
    set gNodes to gNodes + 1
    try
        if my roleIs(e, {"AXButton", "AXCheckBox", "AXSwitch", "AXRadioButton", "AXMenuItem", "AXLink", "AXPopUpButton"}) then
            set l to my elementLabel(e)
            repeat with k in keywords
                ignoring case
                    if l contains (k as text) then
                        set end of gFound to e
                        exit repeat
                    end if
                end ignoring
            end repeat
        end if
    end try
    try
        tell application "System Events" to set kids to UI elements of e
    on error
        return
    end try
    repeat with c in kids
        my walk(c, depth + 1, maxDepth, keywords)
    end repeat
end walk

on inspectWalk(e, depth, maxDepth)
    global gInspect, gInspectCount
    if gInspectCount > 400 then return
    if depth > maxDepth then return
    set gInspectCount to gInspectCount + 1
    try
        set r to my roleOf(e)
        set l to my elementLabel(e)
        set v to ""
        try
            set v to (my valueOf(e) as text)
        end try
        set p to ""
        try
            set p to (my positionOf(e) as text)
        end try
        set end of gInspect to r & " | " & l & " | " & v & " | " & p
    end try
    try
        tell application "System Events" to set kids to UI elements of e
    on error
        return
    end try
    repeat with c in kids
        my inspectWalk(c, depth + 1, maxDepth)
    end repeat
end inspectWalk

on findElements(keywords, whichArea)
    global gFound, gNodes
    set gFound to {}
    set gNodes to 0
    set root to my rootFor(whichArea)
    if root is not missing value then my walk(root, 0, 32, keywords)
    return gFound
end findElements

on pressElement(e)
    try
        tell application "System Events" to perform action "AXPress" of e
        return true
    on error
        try
            tell application "System Events" to click e
            return true
        end try
    end try
    return false
end pressElement

on clickTopRight(keywords, whichArea)
    set elems to my findElements(keywords, whichArea)
    set best to missing value
    set bestScore to -1000000
    repeat with e in elems
        try
            set p to my positionOf(e)
            if p is not missing value then
                set x to item 1 of p
                set y to item 2 of p
                set score to x - y
                if score > bestScore then
                    set best to e
                    set bestScore to score
                end if
            end if
        end try
    end repeat
    if best is not missing value then
        if my pressElement(best) then return "CLICKED"
    end if
    -- Si no hay posiciones, usar el primero.
    return my clickFirst(keywords, whichArea, 1)
end clickTopRight

on clickFirst(keywords, whichArea, limit)
    set elems to my findElements(keywords, whichArea)
    set n to 0
    repeat with e in elems
        try
            if my pressElement(e) then
                set n to n + 1
                if n >= limit then return "CLICKED"
            end if
        end try
    end repeat
    if n > 0 then return "CLICKED"
    return "NO_BUTTON"
end clickFirst

on inspectCanva()
    global gInspect, gInspectCount
    set gInspect to {}
    set gInspectCount to 0
    set root to my rootFor("dialog")
    if root is missing value then set root to my rootFor("window")
    if root is missing value then return "NO_WINDOW"
    my inspectWalk(root, 0, 32)
    return gInspect as text
end inspectCanva
