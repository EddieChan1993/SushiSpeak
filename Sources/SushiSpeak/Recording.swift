import Foundation

struct Recording: Identifiable {
    let id: UUID
    let url: URL
    let date: Date
    let duration: TimeInterval

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    var formattedDuration: String {
        let t = Int(duration)
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
