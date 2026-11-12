#Requires AutoHotkey v2.0

class KweetyCore {
    static Aliases(trigger) {
        en := "qwertyuiop[]asdfghjkl;'zxcvbnm,.``"
        ru := "йцукенгшщзхъфывапролджэячсмитьбюё"
        trigger := StrLower(trigger)
        alternate := ""
        Loop Parse trigger {
            ch := A_LoopField
            if p := InStr(en, ch, true)
                alternate .= SubStr(ru, p, 1)
            else if p := InStr(ru, ch, true)
                alternate .= SubStr(en, p, 1)
            else
                alternate .= ch
        }
        return alternate = trigger ? [trigger] : [trigger, alternate]
    }

    static Validate(items) {
        used := Map()
        for item in items {
            if !RegExMatch(item.Trigger, "i)^[a-zа-яё0-9_-]{1,40}\z")
                throw Error("Сокращение: от 1 до 40 букв, цифр, знаков _ или -.")
            if item.Text = ""
                throw Error("Введите текст для подстановки.")
            if StrLen(item.Text) > 50000
                throw Error("Текст слишком длинный: максимум 50 000 символов.")
            for alias in this.Aliases(item.Trigger) {
                if used.Has(alias)
                    throw Error("Сокращение «" item.Trigger "» совпадает с «" used[alias] "» в одной из раскладок.")
                used[alias] := item.Trigger
            }
        }
    }

    ; Separate text from keystrokes: literal braces and !^+# never become commands.
    static Plan(value) {
        value := StrReplace(StrReplace(value, "`r`n", "`n"), "`r", "`n")
        result := []
        for i, line in StrSplit(value, "`n") {
            if i > 1
                result.Push({Kind: "key", Value: "+{Enter}"})
            if line != ""
                result.Push({Kind: "text", Value: line})
        }
        return result
    }

    ; Compile once when templates change, not while the user is typing.
    ; Explicit Unicode tokens keep template content out of Send's command syntax.
    static CompileSend(value) {
        result := ""
        for step in this.Plan(value) {
            if step.Kind = "key" {
                result .= step.Value
                continue
            }
            Loop Parse step.Value {
                ch := A_LoopField
                if ch = "`t"
                    result .= "{Tab}"
                else
                    result .= "{U+" Format("{:04X}", Ord(ch)) "}"
            }
        }
        return result
    }

    static CompileBatches(value) {
        batches := [], current := "", count := 0
        for step in this.Plan(value) {
            if step.Kind = "key" {
                if count >= 1000 {
                    batches.Push(current)
                    current := "", count := 0
                }
                current .= step.Value
                count += 1
                continue
            }
            Loop Parse step.Value {
                code := Ord(A_LoopField)
                ; Keep UTF16 surrogate pairs together at a batch boundary.
                if count >= 1000 && !(code >= 0xDC00 && code <= 0xDFFF) {
                    batches.Push(current)
                    current := "", count := 0
                }
                current .= code = 9 ? "{Tab}" : "{U+" Format("{:04X}", code) "}"
                count += 1
            }
        }
        if current != ""
            batches.Push(current)
        return batches
    }

    static Encode(value) {
        buf := Buffer(StrPut(value, "UTF-8"))
        len := StrPut(value, buf, "UTF-8") - 1
        hex := ""
        Loop len
            hex .= Format("{:02X}", NumGet(buf, A_Index - 1, "UChar"))
        return hex
    }

    static Decode(hex) {
        if Mod(StrLen(hex), 2) || RegExMatch(hex, "[^0-9A-Fa-f]")
            throw Error("Повреждён текст в файле настроек.")
        buf := Buffer(StrLen(hex) // 2 + 1, 0)
        Loop StrLen(hex) // 2
            NumPut("UChar", Integer("0x" SubStr(hex, A_Index * 2 - 1, 2)), buf, A_Index - 1)
        return StrGet(buf, "UTF-8")
    }
}

class KweetyStore {
    static Defaults() => {Enabled: 1, FastPaste: 1, Space: 1, Enter: 1, Tab: 0,
        Items: [{Trigger: "fff", Text: "Привет это тестовое сообщение"}]}

    static Load(path) {
        if !FileExist(path)
            return this.Defaults()
        ; Parse the file ourselves: Windows INI APIs truncate very long values.
        data := Map()
        section := ""
        for line in StrSplit(FileRead(path), "`n", "`r") {
            if line = ""
                continue
            if RegExMatch(line, "^\[([^\]]+)\]$", &match) {
                section := match[1]
                if data.Has(section)
                    throw Error("Повторный раздел настроек: " section)
                data[section] := Map()
            } else {
                p := InStr(line, "=")
                if !p || !data.Has(section)
                    throw Error("Повреждён файл настроек.")
                key := SubStr(line, 1, p - 1)
                if data[section].Has(key)
                    throw Error("Повторная настройка: " key)
                data[section][key] := SubStr(line, p + 1)
            }
        }
        if this.Read(data, "Kweety", "Version") != "1"
            throw Error("Неизвестный формат настроек. Файл: " path)
        cfg := {Items: []}
        for name in ["Enabled", "Space", "Enter", "Tab"] {
            value := this.Read(data, "Kweety", name)
            if value != "0" && value != "1"
                throw Error("Повреждена настройка: " name)
            cfg.%name% := Integer(value)
        }
        fastPaste := data["Kweety"].Has("FastPaste") ? this.Read(data, "Kweety", "FastPaste") : "1"
        if fastPaste != "0" && fastPaste != "1"
            throw Error("Повреждена настройка: FastPaste")
        cfg.FastPaste := Integer(fastPaste)
        if !cfg.Space && !cfg.Enter && !cfg.Tab
            throw Error("В настройках не выбрана клавиша замены.")
        count := this.Read(data, "Kweety", "Count")
        if !RegExMatch(count, "^\d+$") || Integer(count) > 1000
            throw Error("Повреждён список сокращений.")
        Loop Integer(count) {
            section := "Snippet" A_Index
            cfg.Items.Push({Trigger: this.Read(data, section, "Trigger"),
                Text: KweetyCore.Decode(this.Read(data, section, "Text"))})
        }
        KweetyCore.Validate(cfg.Items)
        return cfg
    }

    static Read(data, section, key) {
        if !data.Has(section) || !data[section].Has(key)
            throw Error("Отсутствует настройка: " section "/" key)
        return data[section][key]
    }

    static Save(path, cfg) {
        KweetyCore.Validate(cfg.Items)
        if cfg.Items.Length > 1000
            throw Error("Можно сохранить не более 1000 шаблонов.")
        if !cfg.Space && !cfg.Enter && !cfg.Tab
            throw Error("Выберите хотя бы одну клавишу замены.")
        SplitPath(path, , &dir)
        DirCreate(dir)
        content := "[Kweety]`r`nVersion=1`r`nCount=" cfg.Items.Length "`r`n"
        for name in ["Enabled", "FastPaste", "Space", "Enter", "Tab"]
            content .= name "=" cfg.%name% "`r`n"
        for i, item in cfg.Items
            content .= "`r`n[Snippet" i "]`r`nTrigger=" item.Trigger "`r`nText=" KweetyCore.Encode(item.Text) "`r`n"
        temp := path ".tmp"
        try {
            file := FileOpen(temp, "w", "UTF-16")
            file.Write(content)
            file.Close()
            if FileExist(path)
                FileCopy(path, path ".bak", true)
            FileMove(temp, path, true)
        } finally {
            if FileExist(temp)
                FileDelete(temp)
        }
    }
}
