#Requires AutoHotkey v2.0

class KweetyLayout {
    ; Keep the original spacing; grow the main working area and anchor its footer.
    static Enable(window, workspace) {
        window.Opt("+Resize")
        window.Show("Hide AutoSize")
        layout := KweetyLayout(window, workspace)
        window.OnEvent("Size", layout.Resize.Bind(layout))
        return layout
    }

    __New(window, workspace) {
        window.GetClientPos(, , &width, &height)
        this.Width := width, this.Height := height
        this.Workspace := workspace
        workspace.GetPos(, &top, , &workHeight)
        this.Controls := []
        for control in window {
            control.GetPos(&x, &y, &w, &h)
            this.Controls.Push({Control: control, X: x, Y: y, W: w, H: h,
                Stretch: control.Hwnd = workspace.Hwnd || (w > width / 2 && control.Type != "Button"),
                Grow: control.Hwnd = workspace.Hwnd, Footer: y >= top + workHeight})
        }
        window.Opt("+MinSize" width "x" (height - workHeight + Min(80, workHeight)))
    }

    Resize(window, state, width, height) {
        if state = -1
            return
        dx := width - this.Width, dy := height - this.Height
        for item in this.Controls {
            item.Control.Move(item.X, item.Y + (item.Footer ? dy : 0),
                item.W + (item.Stretch ? dx : 0), item.H + (item.Grow ? dy : 0))
            if item.Control.Type = "ListView" {
                columns := SendMessage(0x101F, 0, 0, item.Control.Hwnd) ; LVM_GETHEADER
                count := SendMessage(0x1200, 0, 0, columns) ; HDM_GETITEMCOUNT
                remaining := item.W + dx - 28
                Loop count - 1
                    remaining -= SendMessage(0x101D, A_Index - 1, 0, item.Control.Hwnd)
                item.Control.ModifyCol(count, Max(80, remaining))
            }
        }
        ; Moving static controls can leave their old text painted on the parent.
        ; Erase and repaint the entire client area and all children together.
        DllCall("RedrawWindow", "Ptr", window.Hwnd, "Ptr", 0, "Ptr", 0,
            "UInt", 0x185) ; INVALIDATE | ERASE | ALLCHILDREN | UPDATENOW
    }
}
