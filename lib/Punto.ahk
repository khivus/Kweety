#Requires AutoHotkey v2.0

class KweetyPunto {
    ; PSRF layout documented by the author of a working decoder:
    ; https://www.programmersforum.rocks/t/punto-switcher-replace-dat/5448/20
    static Read(path) {
        file := FileOpen(path, "r")
        if file.Length > 16000000
            throw Error("Файл Punto слишком большой.")
        data := Buffer(file.Length)
        file.RawRead(data)
        file.Close()
        return this.Decode(data)
    }

    static Decode(data) {
        if data.Size < 4 || StrGet(data, 4, "CP0") != "PSRF"
            throw Error("Неизвестный формат replace.dat: ожидается сигнатура PSRF.")
        offset := 4, items := []
        while offset < data.Size {
            if offset + 5 > data.Size
                throw Error("Оборван заголовок записи Punto.")
            size := NumGet(data, offset, "UInt")
            if size < 9 || Mod(size - 5, 2) || offset + size > data.Size
                throw Error("Повреждена длина записи Punto.")
            plain := Buffer(size - 5), seed := 0x91DAFA48
            Loop plain.Size {
                seed := (seed * 214013 + 2531011) & 0xFFFFFFFF
                NumPut("UChar", NumGet(data, offset + 4 + A_Index, "UChar") ^ ((seed >> 16) & 255), plain, A_Index - 1)
            }
            parts := [], start := 0
            Loop plain.Size // 2 {
                pos := (A_Index - 1) * 2
                if NumGet(plain, pos, "UShort") = 0 {
                    parts.Push(pos = start ? "" : StrGet(plain.Ptr + start, (pos - start) // 2, "UTF-16"))
                    start := pos + 2
                }
            }
            if parts.Length != 2 || start != plain.Size
                throw Error("Не удалось прочитать пару сокращение/текст в replace.dat.")
            items.Push({Trigger: StrLower(Trim(parts[1])), Text: parts[2]})
            if items.Length > 10000
                throw Error("Слишком много записей в файле Punto.")
            offset += size
        }
        return items
    }

    static Merge(existing, incoming) {
        merged := existing.Clone(), skipped := []
        for item in incoming {
            candidate := merged.Clone()
            candidate.Push(item)
            try {
                KweetyCore.Validate(candidate)
                if candidate.Length > 1000
                    throw Error("Достигнут предел 1000 шаблонов.")
                merged := candidate
            } catch as err
                skipped.Push(item.Trigger ": " err.Message)
        }
        return {Items: merged, Added: merged.Length - existing.Length, Skipped: skipped}
    }

    static Find() {
        for sub in ["User Data", "3.0", ""] {
            path := A_AppData "\Yandex\Punto Switcher\" sub "\replace.dat"
            if FileExist(path)
                return path
        }
        return ""
    }

    static Preferences(path) {
        result := {Keys: Map(), Excluded: [], Startup: -1, Summary: ""}
        if !FileExist(path) {
            result.Summary := "preferences.xml рядом не найден. Импортируются только сокращения."
            return result
        }
        if FileGetSize(path) > 2000000
            throw Error("Слишком большой preferences.xml.")
        xml := ComObject("MSXML2.DOMDocument.6.0")
        xml.async := false
        xml.resolveExternals := false
        xml.setProperty("ProhibitDTD", true)
        if !xml.load(path) || xml.documentElement.nodeName != "PuntoSwitcherSettings"
            throw Error("Неизвестный формат preferences.xml.")
        for name, properties in Map("ReplaceOnSpace", ["Space"], "ReplaceOnEnterAndTab", ["Enter", "Tab"]) {
            node := xml.selectSingleNode("/PuntoSwitcherSettings/" name)
            if node && (node.text = "Yes" || node.text = "No") {
                for property in properties
                    result.Keys[property] := node.text = "Yes" ? 1 : 0
            }
        }
        node := xml.selectSingleNode("/PuntoSwitcherSettings/RunAtStartup")
        if node && (node.text = "Yes" || node.text = "No")
            result.Startup := node.text = "Yes" ? 1 : 0
        node := xml.selectSingleNode("/PuntoSwitcherSettings/ProgramsExceptions")
        if node {
            for rule in StrSplit(RegExReplace(node.text, "[,;\r]", "`n"), "`n") {
                rule := Trim(rule, " `t" Chr(34))
                if RegExMatch(rule, "i)^[^<>|*?`"\r\n]+\.exe$")
                    result.Excluded.Push(rule)
            }
        }
        details := ""
        for key, value in result.Keys
            details .= key "=" (value ? "Да" : "Нет") "; "
        names := ""
        for rule in result.Excluded
            names .= (names = "" ? "" : "; ") rule
        result.Summary := "Клавиши: " (details = "" ? "не указаны" : details) "`nПрограммы: " (names = "" ? "не указаны" : names) "`n"
            . "Автозапуск Punto: " (result.Startup = -1 ? "не указан" : result.Startup ? "включён" : "выключен") ".`n"
            . "Горячие клавиши Punto, дневник, правила автопереключения, бинарные prog_ex.dat и исключения заголовков не переносятся."
        return result
    }
}
