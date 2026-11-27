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

    @Published var focusMinutes: Int = 25 { didSet { durationsChanged() } }
    @Published var shortMinutes: Int = 5 { didSet { durationsChanged() } }
    @Published var longMinutes: Int = 15 { didSet { durationsChanged() } }

    private var timer: Timer?
    private var loading = true
    private let defaults = UserDefaults.standard
    private static let key = "folio.pomodoro"

    var isRunning: Bool { endDate != nil }
    /// Running, or paused part-way through.
    var isActive: Bool { isRunning || remaining < duration(of: phase) - 0.5 }

    func duration(of p: Phase) -> TimeInterval {
        switch p {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortMinutes * 60)
        case .longBreak: return TimeInterval(longMinutes * 60)
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
            focusMinutes = d["focus"] as? Int ?? 25
            shortMinutes = d["short"] as? Int ?? 5
            longMinutes = d["long"] as? Int ?? 15
            remaining = d["remaining"] as? Double ?? TimeInterval(focusMinutes * 60)
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
                                "focus": focusMinutes, "short": shortMinutes, "long": longMinutes]
        if let endDate { d["end"] = endDate.timeIntervalSince1970 }
        defaults.set(d, forKey: Self.key)
    }
}

/// The timer's popover: phase, a countdown ring, start/pause, and the session lengths.
struct PomodoroPanel: View {
    @ObservedObject var timer: Pomodoro

    var body: some View {
        VStack(spacing: 18) {
            Text("Pomodoro Timer")
                .font(.system(size: 19, weight: .semibold))

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
                minutes("Focus", $timer.focusMinutes, 5...90, step: 5)
                Divider().padding(.leading, 14)
                minutes("Short Break", $timer.shortMinutes, 1...30, step: 1)
                Divider().padding(.leading, 14)
                minutes("Long Break", $timer.longMinutes, 5...45, step: 5)
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

    private func minutes(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) min")
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
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
