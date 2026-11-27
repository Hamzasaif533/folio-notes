import SwiftUI
import UserNotifications
import AudioToolbox

/// A Pomodoro timer shared by every notebook: focus, then a short break, with a long break
/// after every fourth focus session. Keeps running while the app is closed.
@MainActor
final class Pomodoro: ObservableObject {
    static let shared = Pomodoro()

    enum Phase: String, CaseIterable, Identifiable {
        case focus, shortBreak, longBreak
        var id: String { rawValue }
        var title: String {
            switch self {
            case .focus: return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            }
        }
        var color: Color {
            switch self {
            case .focus: return Color(hex: "#E5533D")
            case .shortBreak: return Color(hex: "#34A86B")
            case .longBreak: return Color(hex: "#3A7BD5")
            }
        }
    }

    @Published private(set) var phase: Phase = .focus
    /// When the running timer ends (nil while stopped or paused).
    @Published private(set) var endDate: Date?
    /// Time left while paused or stopped.
    @Published private(set) var remaining: TimeInterval = 25 * 60
    /// Focus sessions finished in the current round of four.
    @Published private(set) var sessions = 0
    /// Set for a moment when a phase ends, so the editor can say so.
    @Published var finished: Phase?

    /// Lengths in seconds (typed as minutes and seconds).
    @Published var focusSeconds: Int = 25 * 60 { didSet { durationsChanged() } }
    @Published var shortSeconds: Int = 5 * 60 { didSet { durationsChanged() } }
    @Published var longSeconds: Int = 15 * 60 { didSet { durationsChanged() } }
    /// Goes up each time a phase ends, so the screen edges can flash.
    @Published private(set) var flashCount = 0
    @Published private(set) var flashColor: Color = Phase.focus.color

    private var timer: Timer?
    private var loading = true
    private let defaults = UserDefaults.standard
    private static let key = "folio.pomodoro"

    var isRunning: Bool { endDate != nil }
    /// Running, or paused part-way through.
    var isActive: Bool { isRunning || remaining < duration(of: phase) - 0.5 }

    func duration(of p: Phase) -> TimeInterval {
        switch p {
        case .focus: return TimeInterval(max(focusSeconds, 5))
        case .shortBreak: return TimeInterval(max(shortSeconds, 5))
        case .longBreak: return TimeInterval(max(longSeconds, 5))
        }
    }

    func timeLeft(at now: Date = Date()) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return remaining
    }

    func progress(at now: Date = Date()) -> Double {
        let total = duration(of: phase)
        return total > 0 ? 1 - timeLeft(at: now) / total : 0
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private init() {
        if let d = defaults.dictionary(forKey: Self.key) {
            phase = Phase(rawValue: d["phase"] as? String ?? "") ?? .focus
            sessions = d["sessions"] as? Int ?? 0
            focusSeconds = d["focusS"] as? Int ?? (d["focus"] as? Int ?? 25) * 60
            shortSeconds = d["shortS"] as? Int ?? (d["short"] as? Int ?? 5) * 60
            longSeconds = d["longS"] as? Int ?? (d["long"] as? Int ?? 15) * 60
            remaining = d["remaining"] as? Double ?? TimeInterval(focusSeconds)
            if let end = d["end"] as? Double { endDate = Date(timeIntervalSince1970: end) }
        }
        loading = false
        refresh()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: Controls

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = duration(of: phase) }
        endDate = Date().addingTimeInterval(remaining)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        schedule()
        save()
    }

    func pause() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        schedule()
        save()
    }

    func toggle() { isRunning ? pause() : start() }

    /// Back to the start of the current phase.
    func reset() {
        endDate = nil
        remaining = duration(of: phase)
        schedule()
        save()
    }

    /// Reset everything: a fresh round of four, starting with focus.
    func resetAll() {
        endDate = nil
        phase = .focus
        sessions = 0
        remaining = duration(of: .focus)
        schedule()
        save()
    }

    func select(_ p: Phase) {
        endDate = nil
        phase = p
        remaining = duration(of: p)
        schedule()
        save()
    }

    /// Ends the current phase now and moves on to the next one.
    func skip() { advance(counted: false) }

    // MARK: Internals

    private func durationsChanged() {
        guard !loading, !isRunning else { return }
        remaining = duration(of: phase)
        save()
    }

    /// Checks whether the running timer ran out (also while the app was closed).
    private func refresh() {
        if let endDate, endDate <= Date() {
            advance(counted: true)
        } else {
            schedule()
        }
    }

    private func advance(counted: Bool) {
        let ended = phase
        let wasRunning = isRunning
        if ended == .focus {
            sessions += 1
            phase = sessions >= 4 ? .longBreak : .shortBreak
        } else {
            if ended == .longBreak { sessions = 0 }
            phase = .focus
        }
        endDate = nil
        remaining = duration(of: phase)
        if counted && wasRunning {
            finished = ended
            flashColor = ended.color
            flashCount += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1005)
        }
        schedule()
        save()
    }

    /// Wakes the app when the timer ends, and posts a notification for when it's closed.
    private func schedule() {
        timer?.invalidate()
        timer = nil
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.key])
        guard let endDate else { return }
        let t = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let ended = phase
        let id = Self.key
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = ended == .focus ? "Focus session done" : "Break's over"
            content.body = ended == .focus ? "Time for a break." : "Back to it: time to focus."
            content.sound = .default
            let wait = max(1, endDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private func save() {
        guard !loading else { return }
        var d: [String: Any] = ["phase": phase.rawValue, "sessions": sessions, "remaining": remaining,
                                "focusS": focusSeconds, "shortS": shortSeconds, "longS": longSeconds]
        if let endDate { d["end"] = endDate.timeIntervalSince1970 }
        defaults.set(d, forKey: Self.key)
    }
}

/// The timer's popover: phase, a countdown ring, start/pause, and the session lengths.
struct PomodoroPanel: View {
    @ObservedObject var timer: Pomodoro

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Pomodoro Timer")
                    .font(.system(size: 19, weight: .semibold))
                Spacer()
                if focused != nil {
                    Button("Done") { focused = nil }
                        .font(.body.weight(.semibold))
                }
            }

            Picker("Phase", selection: Binding(get: { timer.phase }, set: { timer.select($0) })) {
                ForEach(Pomodoro.Phase.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: max(0.001, 1 - timer.progress(at: ctx.date)))
                        .stroke(timer.phase.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: timer.progress(at: ctx.date))
                    VStack(spacing: 4) {
                        Text(Pomodoro.format(timer.timeLeft(at: ctx.date)))
                            .font(.system(size: 46, weight: .semibold, design: .rounded).monospacedDigit())
                        Text(timer.isRunning ? timer.phase.title : (timer.isActive ? "Paused" : "Ready"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 190, height: 190)
            }

            // Focus sessions in this round of four.
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < timer.sessions ? Pomodoro.Phase.focus.color : Color.white.opacity(0.15))
                        .frame(width: 10, height: 10)
                }
            }
            .accessibilityLabel("\(timer.sessions) of 4 focus sessions done")

            HStack(spacing: 12) {
                round("arrow.counterclockwise", "Reset") { timer.reset() }
                Button { timer.toggle() } label: {
                    Label(timer.isRunning ? "Pause" : (timer.isActive ? "Resume" : "Start"),
                          systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 150, height: 50)
                        .background(Capsule().fill(timer.phase.color))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                round("forward.end.fill", "Skip") { timer.skip() }
            }

            VStack(spacing: 0) {
                length("Focus", $timer.focusSeconds)
                Divider().padding(.leading, 14)
                length("Short Break", $timer.shortSeconds)
                Divider().padding(.leading, 14)
                length("Long Break", $timer.longSeconds)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#1C1C1E")))

            if timer.sessions > 0 {
                Button("Start a New Round") { timer.resetAll() }
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(18)
        .foregroundStyle(.white)
        .tint(timer.phase.color)
        .animation(.snappy(duration: 0.2), value: timer.phase)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
        .darkPanel()
    }

    private func round(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(label)
    }

    /// A length you type as minutes and seconds.
    private func length(_ title: String, _ total: Binding<Int>) -> some View {
        let mins = Binding<Int>(get: { total.wrappedValue / 60 },
                                set: { total.wrappedValue = Self.clampTotal(min(max($0, 0), 600) * 60 + total.wrappedValue % 60) })
        let secs = Binding<Int>(get: { total.wrappedValue % 60 },
                                set: { total.wrappedValue = Self.clampTotal(total.wrappedValue / 60 * 60 + min(max($0, 0), 59)) })
        return HStack(spacing: 6) {
            Text(title)
            Spacer()
            numberField(mins, focus: .init(title: title, part: 0))
            Text("min").foregroundStyle(.white.opacity(0.55))
            numberField(secs, focus: .init(title: title, part: 1))
            Text("sec").foregroundStyle(.white.opacity(0.55))
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private static func clampTotal(_ s: Int) -> Int { max(s, 0) }

    struct FieldID: Hashable { let title: String; let part: Int }
    @FocusState private var focused: FieldID?

    private func numberField(_ value: Binding<Int>, focus: FieldID) -> some View {
        // Typed digits apply straight away (the number pad has no return key).
        let text = Binding<String>(get: { String(value.wrappedValue) },
                                   set: { value.wrappedValue = Int(String($0.filter { $0.isNumber }.prefix(3))) ?? 0 })
        return TextField("0", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .focused($focused, equals: focus)
            .frame(width: 48, height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(focused == focus ? 0.16 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focused == focus ? timer.phase.color : Color.clear, lineWidth: 1.5))
    }
}

/// When a Pomodoro phase ends, the edges of the screen glow and pulse a few times.
struct PomodoroEdgeFlash: View {
    @ObservedObject var timer: Pomodoro
    @State private var glow = false
    @State private var visible = false

    var body: some View {
        ZStack {
            if visible {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(timer.flashColor, lineWidth: 10)
                    .blur(radius: 6)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(timer.flashColor.opacity(0.9), lineWidth: 4))
                    .opacity(glow ? 1 : 0.15)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: timer.flashCount) { _, _ in pulse() }
    }

    private func pulse() {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.15)) { visible = true }
            for _ in 0..<4 {
                withAnimation(.easeInOut(duration: 0.35)) { glow = true }
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.easeInOut(duration: 0.35)) { glow = false }
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            withAnimation(.easeOut(duration: 0.4)) { visible = false }
        }
    }
}

/// A small countdown shown on the page while a Pomodoro is running or paused.
struct PomodoroPill: View {
    @ObservedObject var timer: Pomodoro

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 7) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.001, 1 - timer.progress(at: ctx.date)))
                        .stroke(timer.phase.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                Text(Pomodoro.format(timer.timeLeft(at: ctx.date)))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                if !timer.isRunning {
                    Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .accessibilityLabel("Pomodoro \(timer.phase.title), \(Pomodoro.format(timer.timeLeft())) left")
    }
}

/// The toolbar's timer icon, lit while a Pomodoro is going.
struct PomodoroToolIcon: View {
    @ObservedObject var timer: Pomodoro

    var body: some View {
        let on = timer.isActive
        Image(systemName: "timer")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(on ? timer.phase.color : Color.primary)
            .frame(width: 44, height: 38)
            .background(Capsule().fill(on ? timer.phase.color.opacity(0.2) : Color.clear))
            .contentShape(Rectangle())
    }
}

/// Shows the countdown pill while a Pomodoro is going, and reports when a phase ends.
struct PomodoroBadge: View {
    @ObservedObject var timer: Pomodoro
    let onTap: () -> Void
    let onFinish: (Pomodoro.Phase) -> Void

    var body: some View {
        ZStack {
            if timer.isActive {
                Button(action: onTap) { PomodoroPill(timer: timer) }
                    .buttonStyle(PressableStyle())
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: timer.isActive)
        .onChange(of: timer.finished) { _, f in
            guard let f else { return }
            onFinish(f)
            timer.finished = nil
        }
    }
}
