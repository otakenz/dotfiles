; Voice input: hold Ctrl+Q in WezTerm, talk, release -> text is typed.
; Ctrl+Shift+Q toggles "type only" / "send right away" (adds Enter).
; Talks to the voice-input service in WSL on 127.0.0.1:47821.
; Installed and started by voice-input/install-windows.sh in the dotfiles.

#Requires AutoHotkey v2.0
#SingleInstance Force

global URL := "http://127.0.0.1:47821"
global AutoEnter := false
global Busy := false
A_IconTip := "Voice input (hold Ctrl+Q in WezTerm)"

#HotIf WinActive("ahk_exe wezterm-gui.exe")
^q:: Dictate()
^+q:: ToggleMode()
#HotIf

Dictate() {
    global Busy
    if Busy
        return
    Busy := true
    try {
        RunDictation()
    } finally {
        Busy := false
    }
}

RunDictation() {
    target := WinExist("A")
    r := Post("/start", 2000)
    if (r = "") {
        Tip("voice service not running")
        return
    }
    if !InStr(r, '"ok": true') {
        Tip(JsonField(r, "warning"))
        return
    }
    Tip("🎙 listening", 0)
    while GetKeyState("q", "P") && GetKeyState("Ctrl", "P")
        Sleep(20)
    Tip("… transcribing", 0)
    r := Post("/stop", 20000)
    if (r = "") {
        Tip("voice service not running")
        return
    }
    text := StrReplace(StrReplace(JsonField(r, "text"), "`r", " "), "`n", " ")
    warning := JsonField(r, "warning")
    if (text = "") {
        if (warning != "")
            Tip(warning)
        else
            ClearTip()
        return
    }
    ; Typing while Ctrl is still down would turn letters into shortcuts.
    if !KeyWait("Ctrl", "T5") {
        Tip("not typed – Ctrl still held")
        return
    }
    if !WinActive("ahk_id " target) {
        Tip("not typed – WezTerm lost focus")
        return
    }
    ClearTip()
    SendText(text)
    if AutoEnter
        Send("{Enter}")
}

ToggleMode() {
    global AutoEnter
    AutoEnter := !AutoEnter
    Tip(AutoEnter ? "Voice: send right away" : "Voice: type only")
}

; Returns the response body, or "" when the service cannot be reached.
Post(path, timeoutMs) {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetProxy(1)  ; direct, never the system proxy
        req.SetTimeouts(timeoutMs, timeoutMs, timeoutMs, timeoutMs)
        req.Open("POST", URL path, false)
        req.SetRequestHeader("X-Voice-Input", "1")
        req.Send("")
        return req.ResponseText
    } catch {
        return ""
    }
}

; Reads a string field from the service's flat JSON; "" for null or missing.
JsonField(json, key) {
    if !RegExMatch(json, '"' key '":\s*"((?:[^"\\]|\\.)*)"', &m)
        return ""
    s := m[1]
    out := ""
    i := 1
    while (i <= StrLen(s)) {
        c := SubStr(s, i, 1)
        if (c != "\") {
            out .= c
            i += 1
            continue
        }
        n := SubStr(s, i + 1, 1)
        switch n {
            case "n": out .= "`n"
            case "r": out .= "`r"
            case "t": out .= "`t"
            case "b", "f":
            case "u":
                out .= Chr(Integer("0x" SubStr(s, i + 2, 4)))
                i += 4
            default: out .= n
        }
        i += 2
    }
    return out
}

Tip(msg, ms := 2000) {
    SetTimer(ClearTip, 0)
    ToolTip(msg)
    if ms
        SetTimer(ClearTip, -ms)
}

ClearTip() {
    ToolTip()
}
