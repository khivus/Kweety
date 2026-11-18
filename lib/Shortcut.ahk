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
        key := this.LayoutKeyName(parts[2])
        if key = ""
            throw Error("Неизвестная клавиша: " parts[2])
        if RegExMatch(key, "i)^(l|r)?(control|ctrl|alt|shift|win)$")
            throw Error("Выберите основную клавишу, например F или F8.")
        if !RegExMatch(modifiers, "[\^!#]") && !RegExMatch(key, "i)^(F([1-9]|1[0-9]|2[0-4])|Pause|ScrollLock)$")
            throw Error("Добавьте Ctrl, Alt или Win, либо выберите F1–F24, Pause или ScrollLock.")
        return modifiers key
    }

    static LayoutKeyName(name) {
        ; Older shortcuts saved the character shown by the active Russian layout.
        if RegExMatch(name, "i)^[а-яё]$")
            name := KweetyCore.Aliases(name)[2]
        if RegExMatch(name, "i)^[a-z]$")
            return StrLower(name)
        vk := GetKeyVK(name)
        if vk >= 0x41 && vk <= 0x5A
            return StrLower(Chr(vk))
        if !vk && !GetKeySC(name)
            return ""
        key := StrLower(GetKeyName(name))
        return RegExMatch(key, "^[а-яё]$") ? KweetyCore.Aliases(key)[2] : key
    }

    static Binding(key) {
        if RegExMatch(key, "^([\^!+#]+)([a-z])$", &match)
            key := match[1] Format("vk{:02X}", Ord(StrUpper(match[2])))
        return "$" key
    }

    __New(dialog, value) {
        this.Recorded := value
        this.Field := dialog.AddButton("xm y+6 w400", this.Label())
        this.Field.OnEvent("Click", (*) => this.Record())
        dialog.AddButton("x+8 yp w90", "Очистить").OnEvent("Click", (*) => this.Clear())
    }

    Label() {
        label := ""
        for entry in [["^", "Ctrl+"], ["!", "Alt+"], ["+", "Shift+"], ["#", "Win+"]]
            if InStr(this.Recorded, entry[1])
                label .= entry[2]
        label .= RegExReplace(this.Recorded, "^[\^!+#]+")
        return label = "" ? "Нажмите и введите сочетание…" : label
    }

    Record() {
        this.Field.Text := "Нажмите сочетание (Esc — отмена)…"
        hook := InputHook("T10")
        hook.KeyOpt("{All}", "NS")
        hook.OnKeyDown := this.Capture.Bind(this)
        hook.Start()
        hook.Wait()
        this.Field.Text := this.Label()
    }

    Capture(hook, vk, sc) {
        key := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
        if RegExMatch(key, "i)^(L|R)?(Control|Ctrl|Alt|Shift|Win)$")
            return
        if key = "Escape" {
            hook.Stop()
            return
        }
        modifiers := ""
        for name, symbol in Map("Ctrl", "^", "Alt", "!", "Shift", "+", "LWin", "#", "RWin", "#")
            if GetKeyState(name, "P") && !InStr(modifiers, symbol)
                modifiers .= symbol
        try this.Recorded := KweetyShortcut.Normalize(modifiers key)
        catch {
            this.Field.Text := "Нужен Ctrl, Alt, Win или F1–F24…"
            return
        }
        hook.Stop()
    }

    Value {
        get => KweetyShortcut.Normalize(this.Recorded)
    }

    Clear() {
        this.Recorded := ""
        this.Field.Text := this.Label()
    }
}
