import SwiftUI
import UIKit

/// İnşaatSoft ERP renkleri: lacivert kenar menü (#111e2b), altın vurgu (#d69a42)
enum Tema {
    static let lacivert = Color(hex: "#111e2b")
    static let lacivert2 = Color(hex: "#1b2d40")
    static let altin = Color(hex: "#d69a42")
    static let celik = Color(hex: "#29465b")

    /// Sunucunun renk adları (green, red, orange, blue, purple, teal, slate) ya da #rrggbb
    static func renk(_ ad: String) -> Color {
        switch ad {
        case "green": return Color(hex: "#1f9d55")
        case "red": return Color(hex: "#d64545")
        case "orange": return Color(hex: "#e08a1e")
        case "blue": return Color(hex: "#2f6fdf")
        case "purple": return Color(hex: "#7d4cdb")
        case "teal": return Color(hex: "#13a0a0")
        case "gold", "yellow": return altin
        case "slate", "gray", "grey", "": return Color(.secondaryLabel)
        default: return ad.hasPrefix("#") ? Color(hex: ad) : Color(.secondaryLabel)
        }
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

/// Web panelindeki Font Awesome simge adları → SF Symbols
enum Simge {
    static func ad(_ fa: String) -> String {
        let k = fa.replacingOccurrences(of: "fa-", with: "").replacingOccurrences(of: "fa ", with: "").trimmingCharacters(in: .whitespaces)
        return harita[k] ?? "square.grid.2x2"
    }

    private static let harita: [String: String] = [
        // menü
        "chart-pie": "chart.pie.fill", "chart-line": "chart.line.uptrend.xyaxis", "gauge": "gauge", "house": "house.fill",
        "building": "building.2.fill", "map": "map.fill", "stamp": "seal.fill", "trowel-bricks": "hammer.fill",
        "cart-shopping": "cart.fill", "boxes-stacked": "shippingbox.fill", "box": "shippingbox", "cubes": "cube.fill",
        "truck-field": "truck.box.fill", "id-badge": "person.text.rectangle.fill", "people-carry-box": "person.2.fill",
        "file-contract": "doc.text.fill", "file-invoice-dollar": "doc.richtext.fill", "file-invoice": "doc.plaintext.fill",
        "file-signature": "signature", "file": "doc.fill", "file-lines": "doc.text", "folder-open": "folder.fill",
        "helmet-safety": "checkmark.shield.fill", "house-chimney": "house.lodge.fill", "landmark": "building.columns.fill",
        "money-check-dollar": "banknote.fill", "money-check": "banknote", "money-bill": "banknote.fill", "wallet": "wallet.pass.fill",
        "note-sticky": "note.text", "photo-film": "photo.on.rectangle.angled", "right-left": "arrow.left.arrow.right",
        "scale-balanced": "scalemass.fill", "scale-unbalanced": "scalemass", "triangle-exclamation": "exclamationmark.triangle.fill",
        "calendar-check": "calendar.badge.checkmark", "calendar-day": "calendar", "calendar-days": "calendar",
        "clipboard-list": "list.clipboard.fill", "comments": "bubble.left.and.bubble.right.fill", "envelope-open-text": "envelope.open.fill",
        "envelope": "envelope.fill", "bell": "bell.fill", "user-shield": "lock.shield.fill", "users": "person.3.fill", "user": "person.fill",
        "user-plus": "person.badge.plus", "user-gear": "person.crop.circle.badge.checkmark", "gear": "gearshape.fill", "gears": "gearshape.2.fill",
        "sliders": "slider.horizontal.3", "globe": "globe", "address-book": "person.crop.rectangle.stack.fill", "screwdriver-wrench": "wrench.and.screwdriver.fill",
        "comment-sms": "message.fill", "bullhorn": "megaphone.fill", "paper-plane": "paperplane.fill", "credit-card": "creditcard.fill",
        "receipt": "doc.text.below.ecg", "list-check": "checklist", "check": "checkmark", "check-double": "checkmark.circle.fill",
        "key": "key.fill", "lock": "lock.fill", "shield-halved": "shield.lefthalf.filled", "server": "server.rack",
        "clock-rotate-left": "clock.arrow.circlepath", "location-dot": "mappin.and.ellipse", "city": "building.2",
        // işlemler
        "plus": "plus", "pen-to-square": "square.and.pencil", "pen": "pencil", "trash-can": "trash", "trash": "trash",
        "table-cells": "square.grid.3x3.fill", "phone": "phone.fill", "whatsapp": "message.circle.fill", "reply": "arrowshape.turn.up.left.fill",
        "upload": "square.and.arrow.up", "download": "square.and.arrow.down", "print": "printer.fill", "eye": "eye.fill",
        "image": "photo", "camera": "camera.fill", "magnifying-glass": "magnifyingglass", "filter": "line.3.horizontal.decrease.circle",
        "xmark": "xmark", "ban": "nosign", "rotate": "arrow.clockwise", "share": "square.and.arrow.up", "link": "link",
        "copy": "doc.on.doc", "database": "cylinder.split.1x2.fill", "arrow-up-right-from-square": "arrow.up.right.square", "images": "photo.stack",
        "table-cells-large": "square.grid.2x2.fill", "building-user": "person.crop.square", "palette": "paintpalette.fill", "user-slash": "person.fill.xmark",
        "toggle-on": "switch.2", "share-nodes": "square.and.arrow.up", "file-export": "square.and.arrow.up.on.square", "file-csv": "tablecells",
        "qrcode": "qrcode", "mobile-screen": "iphone", "right-from-bracket": "rectangle.portrait.and.arrow.right", "circle-check": "checkmark.circle.fill",
        "circle-info": "info.circle.fill", "eye-slash": "eye.slash.fill", "envelope-open": "envelope.open", "bell-slash": "bell.slash.fill",
        "broom": "trash.slash", "arrows-rotate": "arrow.triangle.2.circlepath", "floppy-disk": "externaldrive.fill", "cloud": "icloud.fill",
    ]
}
