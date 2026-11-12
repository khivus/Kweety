#Requires AutoHotkey v2.0

class KweetyText {
    static Layout(text) {
        en := "qwertyuiop[]asdfghjkl;'zxcvbnm,.``/"
        ru := "йцукенгшщзхъфывапролджэячсмитьбюё."
        enShift := 'QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>~?'
        ruShift := "ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ,"
        lowerText := StrLower(text)
        fromRussian := StrLen(RegExReplace(lowerText, "[^а-яё]")) > StrLen(RegExReplace(lowerText, "[^a-z]"))
        source := fromRussian ? ru : en, target := fromRussian ? en : ru
        sourceShift := fromRussian ? ruShift : enShift, targetShift := fromRussian ? enShift : ruShift
        result := ""
        Loop Parse text {
            ch := A_LoopField
            if p := InStr(source, ch, true)
                result .= SubStr(target, p, 1)
            else if p := InStr(sourceShift, ch, true)
                result .= SubStr(targetShift, p, 1)
            else
                result .= ch
        }
        return result
    }

    static Case(text) {
        if text == StrUpper(text)
            return StrLower(text)
        if text == StrLower(text)
            return StrTitle(text)
        return StrUpper(text)
    }

    static Matches(item, query) {
        query := StrLower(Trim(query))
        return query = "" || InStr(StrLower(item.Trigger), query, true) || InStr(StrLower(item.Text), query, true)
            || InStr(StrLower(KweetyCore.Aliases(item.Trigger)[-1]), query, true)
    }

    static Excluded(rules, name, path := "") {
        for rule in rules
            if StrLower(rule) = StrLower(name) || StrLower(rule) = StrLower(path)
                return true
        return false
    }
}
