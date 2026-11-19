#Requires AutoHotkey v2.0

class KweetyRich {
    static Escape(text) => StrReplace(StrReplace(StrReplace(StrReplace(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), '"', "&quot;")

    static RtfText(text) {
        out := ""
        Loop Parse StrReplace(text, "`r") {
            ch := A_LoopField, code := Ord(ch)
            if ch = "`n"
                out .= "\par "
            else if ch = "`t"
                out .= "\tab "
            else if ch = "\" || ch = "{" || ch = "}"
                out .= "\" ch
            else if code > 127
                out .= "\u" (code > 32767 ? code - 65536 : code) "?"
            else
                out .= ch
        }
        return out
    }

    static FromRuns(runs) {
        colors := Map(), table := "", body := "", html := "", plain := ""
        for run in runs {
            color := StrUpper(run.Color)
            if !RegExMatch(color, "^[0-9A-F]{6}$")
                color := "000000"
            if !colors.Has(color) {
                colors[color] := colors.Count + 1
                table .= "\red" Integer("0x" SubStr(color, 1, 2)) "\green" Integer("0x" SubStr(color, 3, 2)) "\blue" Integer("0x" SubStr(color, 5, 2)) ";"
            }
            body .= "\cf" colors[color] "\b" (!!run.Bold) "\i" (!!run.Italic) "\ul" (!!run.Underline) " " this.RtfText(run.Text)
            style := "color:#" color ";font-weight:" (run.Bold ? "bold" : "normal") ";font-style:" (run.Italic ? "italic" : "normal") ";text-decoration:" (run.Underline ? "underline" : "none") ";"
            escaped := this.Escape(StrReplace(run.Text, "`r"))
            escaped := StrReplace(StrReplace(StrReplace(escaped, " ", "&nbsp;"), "`t", "&nbsp;&nbsp;&nbsp;&nbsp;"), "`n", "<br>")
            html .= '<span style="' style '">' escaped '</span>'
            plain .= run.Text
        }
        return {Text: plain, Rtf: "{\rtf1\ansi\deff0\uc1{\fonttbl{\f0 Segoe UI;}}{\colortbl;" table "}\f0\fs20 " body "}", Html: '<div style="white-space:pre-wrap">' html '</div>'}
    }

    static Preview(item) {
        runs := this.HtmlRuns(item.Html)
        for run in runs
            run.Text := StrReplace(StrReplace(StrReplace(run.Text, "`r`n", "`n"), "`r", "`n"), "`n", " ↵ ")
        return this.FromRuns(runs)
    }

    static ClipboardHtml(fragment) {
        prefix := "<html><body><!--StartFragment-->", suffix := "<!--EndFragment--></body></html>"
        header := "Version:1.0`r`nStartHTML:{:010}`r`nEndHTML:{:010}`r`nStartFragment:{:010}`r`nEndFragment:{:010}`r`n"
        base := StrPut(Format(header, 0, 0, 0, 0), "UTF-8") - 1
        start := base + StrPut(prefix, "UTF-8") - 1
        finish := start + StrPut(fragment, "UTF-8") - 1
        return Format(header, base, finish + StrPut(suffix, "UTF-8") - 1, start, finish) prefix fragment suffix
    }

    static Entities(text) {
        entities := Map("amp", "&", "lt", "<", "gt", ">", "quot", '"', "apos", "'", "nbsp", " ", "ndash", "–", "mdash", "—", "hellip", "…", "copy", "©", "reg", "®", "euro", "€", "laquo", "«", "raquo", "»", "bull", "•", "trade", "™", "lsquo", "‘", "rsquo", "’", "ldquo", "“", "rdquo", "”")
        out := "", pos := 1
        while RegExMatch(text, "&(#x[0-9a-f]+|#\d+|[a-z]+);", &m, pos) {
            out .= SubStr(text, pos, m.Pos - pos)
            key := m[1], decoded := m[0]
            if entities.Has(key)
                decoded := entities[key]
            else if SubStr(key, 1, 1) = "#" {
                try decoded := Chr(SubStr(key, 2, 1) = "x" ? Integer("0x" SubStr(key, 3)) : Integer(SubStr(key, 2)))
            }
            out .= decoded
            pos := m.Pos + m.Len
        }
        return out SubStr(text, pos)
    }

    static HtmlRuns(html) {
        ; Parse a small, inert text-formatting subset. Never execute HTML/scripts.
        if RegExMatch(html, "is)<!--StartFragment-->(.*?)<!--EndFragment-->", &fragment)
            html := fragment[1]
        else if RegExMatch(html, "is)<body[^>]*>(.*?)</body>", &fragment)
            html := fragment[1]
        html := RegExReplace(html, "is)<(script|style|head)\b[^>]*>.*?</\1\s*>")
        html := RegExReplace(html, "s)<!--.*?-->")
        stack := [{Tag: "root", Color: "000000", Bold: false, Italic: false, Underline: false}], runs := []
        pos := 1, previousBreak := true
        while RegExMatch(html, "s)<[^>]*>|[^<]+", &m, pos) {
            token := m[0], pos := m.Pos + m.Len
            if SubStr(token, 1, 1) != "<" {
                text := this.Entities(token)
                if text != "" {
                    run := stack[-1].Clone(), run.Text := text
                    runs.Push(run)
                    previousBreak := SubStr(text, -1) = "`n"
                }
                continue
            }
            if !RegExMatch(token, "i)^<\s*(/?)\s*([a-z0-9]+)", &tagMatch)
                continue
            tag := StrLower(tagMatch[2]), closing := tagMatch[1] = "/"
            if tag = "br" {
                run := stack[-1].Clone(), run.Text := "`n", runs.Push(run), previousBreak := true
                continue
            }
            if closing {
                moreContent := !RegExMatch(SubStr(html, pos), "is)^\s*(?:</[^>]+>\s*)*$")
                if InStr("|p|div|li|blockquote|h1|h2|h3|", "|" tag "|") && !previousBreak && moreContent {
                    run := stack[-1].Clone(), run.Text := "`n", runs.Push(run), previousBreak := true
                }
                Loop stack.Length - 1 {
                    index := stack.Length - A_Index + 1
                    if stack[index].Tag = tag {
                        while stack.Length >= index
                            stack.Pop()
                        break
                    }
                }
                continue
            }
            if InStr("|img|meta|link|input|hr|wbr|", "|" tag "|")
                continue
            if stack.Length > 128
                throw Error("Слишком глубокая вложенность HTML.")
            style := stack[-1].Clone(), style.Tag := tag
            if tag = "b" || tag = "strong"
                style.Bold := true
            if tag = "i" || tag = "em"
                style.Italic := true
            if tag = "u"
                style.Underline := true
            if RegExMatch(token, "i)(?:^|[;\s`"'])color\s*[:=]\s*[`"']?\s*#([0-9a-f]{6}|[0-9a-f]{3})\b", &color) {
                value := color[1]
                style.Color := StrLen(value) = 3 ? SubStr(value, 1, 1) SubStr(value, 1, 1) SubStr(value, 2, 1) SubStr(value, 2, 1) SubStr(value, 3, 1) SubStr(value, 3, 1) : value
            } else if RegExMatch(token, "i)(?:[;\s`"'])color\s*:\s*rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", &color)
                style.Color := Format("{:02X}{:02X}{:02X}", Min(255, Integer(color[1])), Min(255, Integer(color[2])), Min(255, Integer(color[3])))
            else if RegExMatch(token, "i)(?:[;\s`"'])color\s*[:=]\s*[`"']?\s*(red|black|blue|green|white)\b", &color)
                style.Color := Map("red", "FF0000", "black", "000000", "blue", "0000FF", "green", "008000", "white", "FFFFFF")[StrLower(color[1])]
            if RegExMatch(token, "i)font-weight\s*:\s*(bold|[6-9]00)")
                style.Bold := true
            else if RegExMatch(token, "i)font-weight\s*:\s*(normal|[1-5]00)")
                style.Bold := false
            if RegExMatch(token, "i)font-style\s*:\s*italic")
                style.Italic := true
            else if RegExMatch(token, "i)font-style\s*:\s*normal")
                style.Italic := false
            if RegExMatch(token, "i)text-decoration[^:]*:\s*[^;`"']*underline")
                style.Underline := true
            else if RegExMatch(token, "i)text-decoration[^:]*:\s*none")
                style.Underline := false
            stack.Push(style)
        }
        return runs
    }
}

class KweetyRichEdit {
    __New(gui, options, item) {
        DllCall("LoadLibrary", "Str", "Msftedit.dll", "Ptr")
        this.Control := gui.AddCustom("ClassRICHEDIT50W +0x00201144 +E0x200 " options)
        this.Hwnd := this.Control.Hwnd
        SendMessage(0x435, 50000, 0, this.Hwnd) ; EM_EXLIMITTEXT
        SendMessage(0x443, 0, 0xFFFFFF, this.Hwnd) ; EM_SETBKGNDCOLOR
        if item.HasOwnProp("Rtf") && item.Rtf != ""
            this.StreamIn(item.Rtf)
        else
            this.Control.Text := item.Text
        this.Initial := this.StreamOut()
    }

    Focus() => this.Control.Focus()
    Text => StrReplace(this.GetPlain(), "`r", "`n")

    GetPlain() {
        data := Buffer(100004, 0), request := Buffer(A_PtrSize = 8 ? 32 : 20, 0)
        NumPut("UInt", data.Size, "UInt", 0, "UInt", 1200, request)
        SendMessage(0x45E, request, data, this.Hwnd)
        return StrGet(data, "UTF-16")
    }
    Dirty() => !(this.StreamOut() == this.Initial)

    static StreamCallback(cookie, data, size, written) {
        state := ObjFromPtrAddRef(cookie)
        if state.Input {
            amount := Min(size, state.Buffer.Size - state.Offset)
            if amount
                DllCall("RtlMoveMemory", "Ptr", data, "Ptr", state.Buffer.Ptr + state.Offset, "UPtr", amount)
            state.Offset += amount
        } else {
            copy := Buffer(size)
            DllCall("RtlMoveMemory", "Ptr", copy, "Ptr", data, "UPtr", size)
            state.Chunks.Push(copy)
            amount := size
        }
        NumPut("UInt", amount, written)
        return 0
    }

    StreamIn(rtf, selection := false) {
        buf := Buffer(StrPut(rtf, "CP0") - 1)
        bytes := Buffer(buf.Size + 1)
        StrPut(rtf, bytes, "CP0")
        DllCall("RtlMoveMemory", "Ptr", buf, "Ptr", bytes, "UPtr", buf.Size)
        this.Stream({Input: true, Buffer: buf, Offset: 0}, 0x449, selection ? 0x8002 : 2)
    }

    StreamOut() {
        state := {Input: false, Chunks: []}
        this.Stream(state, 0x44A, 2)
        result := ""
        for chunk in state.Chunks
            result .= StrGet(chunk, chunk.Size, "CP0")
        return result
    }

    Stream(state, message, flags) {
        callback := CallbackCreate((cookie, data, size, written) => KweetyRichEdit.StreamCallback(cookie, data, size, written), "F", 4)
        ; RichEdit structures use 4-byte packing, including on x64.
        stream := Buffer(A_PtrSize * 2 + 4, 0)
        NumPut("Ptr", ObjPtr(state), stream, 0)
        NumPut("Ptr", callback, stream, A_PtrSize + 4)
        try {
            SendMessage(message, flags, stream, this.Hwnd)
            if NumGet(stream, A_PtrSize, "UInt")
                throw Error("Не удалось обработать форматированный текст.")
        } finally CallbackFree(callback)
    }

    Format(kind, value := "") {
        cf := Buffer(116, 0)
        NumPut("UInt", 116, cf)
        SendMessage(0x43A, 1, cf, this.Hwnd)
        if kind = "color" {
            NumPut("UInt", 0x40000000, cf, 4)
            NumPut("UInt", 0, cf, 8)
            rgb := Integer("0x" value)
            NumPut("UInt", ((rgb & 255) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 255), cf, 20)
        } else {
            flag := Map("bold", 1, "italic", 2, "underline", 4)[kind]
            NumPut("UInt", flag, cf, 4)
            NumPut("UInt", NumGet(cf, 8, "UInt") ^ flag, cf, 8)
        }
        SendMessage(0x444, 1, cf, this.Hwnd)
        this.Focus()
    }

    Export() {
        selection := Buffer(8)
        SendMessage(0x434, 0, selection, this.Hwnd)
        text := this.GetPlain(), runs := [], previous := ""
        range := Buffer(8), cf := Buffer(116, 0)
        SendMessage(0xB, 0, 0, this.Hwnd)
        try {
            Loop Parse text {
                index := A_Index - 1
                NumPut("Int", index, "Int", index + 1, range)
                SendMessage(0x437, 0, range, this.Hwnd)
                NumPut("UInt", 116, cf)
                SendMessage(0x43A, 1, cf, this.Hwnd)
                effects := NumGet(cf, 8, "UInt"), color := NumGet(cf, 20, "UInt")
                if effects & 0x40000000
                    color := 0
                rgb := Format("{:02X}{:02X}{:02X}", color & 255, (color >> 8) & 255, (color >> 16) & 255)
                signature := rgb ":" (effects & 7)
                if signature != previous {
                    runs.Push({Text: "", Color: rgb, Bold: !!(effects & 1), Italic: !!(effects & 2), Underline: !!(effects & 4)})
                    previous := signature
                }
                ; RichEdit character positions count a paragraph break as one CR.
                runs[-1].Text .= A_LoopField = "`r" ? "`n" : A_LoopField
            }
        } finally {
            SendMessage(0x437, 0, selection, this.Hwnd)
            SendMessage(0xB, 1, 0, this.Hwnd)
            DllCall("InvalidateRect", "Ptr", this.Hwnd, "Ptr", 0, "Int", true)
        }
        result := KweetyRich.FromRuns(runs)
        result.Rtf := this.StreamOut()
        return result
    }

    PasteFormatted() {
        html := KweetyWindowsClipboard.ReadFormat("HTML Format", "UTF-8")
        if html != "" {
            item := KweetyRich.FromRuns(KweetyRich.HtmlRuns(html))
            this.StreamIn(item.Rtf, true)
        } else
            SendMessage(0x302, 0, 0, this.Hwnd) ; Native RTF/plain paste.
        this.Focus()
    }
}

; Paint rich text directly into the text column using the native RichEdit renderer.
class KweetyTablePreview {
    __New(gui, list, app) {
        this.App := app
        this.Cache := Map()
        this.Renderer := KweetyRichEdit(gui, "Hidden x0 y0 w1 h1", {Text: ""})
        list.OnNotify(-12, this.Draw.Bind(this)) ; NM_CUSTOMDRAW
    }

    Draw(list, data) {
        stage := NumGet(data, A_PtrSize = 8 ? 24 : 12, "UInt")
        if stage = 1 || stage = 0x10001
            return 0x20 ; request item / subitem notifications
        if stage != 0x30001 || NumGet(data, A_PtrSize = 8 ? 88 : 56, "Int") != 2
            return
        index := NumGet(data, A_PtrSize = 8 ? 56 : 36, "UPtr") + 1
        itemIndex := this.App.ItemIndexAt(index)
        if !itemIndex
            return
        item := this.App.Config.Items[itemIndex]
        if !item.HasOwnProp("Formatting") || !item.Formatting || !item.HasOwnProp("Rtf") || item.Rtf = ""
            return
        dc := NumGet(data, A_PtrSize = 8 ? 32 : 16, "Ptr")
        rect := Buffer(16, 0)
        NumPut("Int", 2, rect, 4) ; text subitem
        SendMessage(0x1038, index - 1, rect, list.Hwnd) ; LVM_GETSUBITEMRECT
        left := NumGet(rect, 0, "Int"), top := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int"), bottom := NumGet(rect, 12, "Int")
        saved := DllCall("SaveDC", "Ptr", dc)
        try {
            DllCall("IntersectClipRect", "Ptr", dc, "Int", left, "Int", top, "Int", right, "Int", bottom)
            DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", DllCall("GetSysColorBrush", "Int", 5, "Ptr"))
            if !this.Cache.Has(itemIndex) {
                source := item
                if !item.HasOwnProp("Html") || item.Html = "" {
                    this.Renderer.StreamIn(item.Rtf)
                    source := this.Renderer.Export()
                }
                this.Cache[itemIndex] := KweetyRich.Preview(source).Rtf
            }
            this.Renderer.StreamIn(this.Cache[itemIndex])
            format := Buffer(A_PtrSize * 2 + 40, 0)
            NumPut("Ptr", dc, "Ptr", dc, format)
            dpiX := DllCall("GetDeviceCaps", "Ptr", dc, "Int", 88)
            dpiY := DllCall("GetDeviceCaps", "Ptr", dc, "Int", 90)
            for offset in [A_PtrSize * 2, A_PtrSize * 2 + 16] {
                NumPut("Int", Round((left + 4) * 1440 / dpiX), "Int", Round(top * 1440 / dpiY),
                    "Int", Round(right * 1440 / dpiX), "Int", Round((bottom + 100) * 1440 / dpiY), format, offset)
            }
            NumPut("Int", 0, "Int", -1, format, A_PtrSize * 2 + 32)
            SendMessage(0x439, 1, format, this.Renderer.Hwnd) ; EM_FORMATRANGE
            SendMessage(0x439, 0, 0, this.Renderer.Hwnd)
        } finally {
            DllCall("RestoreDC", "Ptr", dc, "Int", saved)
        }
        return 4 ; CDRF_SKIPDEFAULT
    }
}
