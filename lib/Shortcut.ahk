#Requires AutoHotkey v2.0

; Compose shortcuts explicitly: the user need not hold modifiers while editing.
class KweetyShortcut {
    static Normalize(value) {
        value := Trim(value)
        if value = ""
            return ""
        if !RegExMatch(value, "^([\^!+#]*)([^\^!+#\s]+)$", &parts)
            throw Error("Выберите Ctrl, Alt, Shift или Win и одну клавишу.")
        modifiers := ""
        for symbol in ["^", "!", "+", "#"]
            if InStr(parts[1], symbol)
                modifiers .= symbol
        key := StrLower(parts[2])
        if !GetKeyVK(key) && !GetKeySC(key)
            throw Error("Неизвестная клавиша: " parts[2])
        if RegExMatch(key, "i)^(l|r)?(control|ctrl|alt|shift|win)$")
            throw Error("Выберите основную клавишу, например F или F8.")
        if !RegExMatch(modifiers, "[\^!#]") && !RegExMatch(key, "i)^(F([1-9]|1[0-9]|2[0-4])|Pause|ScrollLock)$")
            throw Error("Добавьте Ctrl, Alt или Win, либо выберите F1–F24, Pause или ScrollLock.")
        return modifiers key
    }

    __New(dialog, value) {
        this.Modifiers := Map()
        for index, entry in [["^", "Ctrl"], ["!", "Alt"], ["+", "Shift"], ["#", "Win"]] {
            control := dialog.AddCheckbox(index = 1 ? "xm y+6 w60" : "x+8 yp w60", entry[2])
            control.Value := InStr(value, entry[1]) > 0
            this.Modifiers[entry[1]] := control
        }
        keys := [""]
        Loop 26
            keys.Push(Chr(64 + A_Index))
        Loop 10
            keys.Push(String(A_Index - 1))
        Loop 24
            keys.Push("F" A_Index)
        for key in ["Space", "Tab", "Enter", "Insert", "Home", "End", "PgUp", "PgDn", "Pause", "ScrollLock"]
            keys.Push(key)
        this.Key := dialog.AddComboBox("x+10 yp-3 w180", keys)
        this.Key.Text := RegExReplace(value, "^[\^!+#]+")
        dialog.AddButton("x+8 yp w75", "Очистить").OnEvent("Click", (*) => this.Clear())
    }

    Value {
        get {
            key := Trim(this.Key.Text)
            if key = ""
                return ""
            modifiers := ""
            for symbol in ["^", "!", "+", "#"]
                if this.Modifiers[symbol].Value
                    modifiers .= symbol
            return KweetyShortcut.Normalize(modifiers key)
        }
    }

    Clear() {
        this.Key.Text := ""
        for symbol, control in this.Modifiers
            control.Value := 0
    }
}
