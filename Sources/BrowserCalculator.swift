import SwiftUI
import WebKit

// MARK: - Calculator

/// A calculator in a popover. Follows the usual order (× and ÷ before + and −).
struct CalculatorPanel: View {
    @AppStorage("folio.calcExpr") private var expr = ""
    @State private var justEvaluated = false

    private let rows: [[String]] = [
        ["AC", "⌫", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["±", "0", ".", "="]
    ]

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(expr.isEmpty ? " " : expr)
                    .font(.system(size: 17, weight: .regular).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(resultText)
                    .font(.system(size: 40, weight: .light).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 6)
            .frame(height: 76)

            VStack(spacing: 10) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { key in button(key) }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .presentationCompactAdaptation(.popover)
        .darkPanel()
    }

    private var resultText: String {
        if expr.isEmpty || expr == "-" { return "0" }
        guard let v = Self.evaluate(expr) else { return "Error" }
        return Self.format(v)
    }

    private func button(_ key: String) -> some View {
        let isOp = ["÷", "×", "−", "+", "="].contains(key)
        let isFn = ["AC", "⌫", "%", "±"].contains(key)
        return Button { press(key) } label: {
            Text(key)
                .font(.system(size: 22, weight: isOp ? .semibold : .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOp ? Theme.action : (isFn ? Color.white.opacity(0.2) : Color.white.opacity(0.09))))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .accessibilityLabel(Self.spoken[key] ?? key)
    }

    private static let spoken = ["AC": "Clear", "⌫": "Delete", "÷": "Divide", "×": "Multiply", "−": "Minus",
                                 "+": "Plus", "±": "Change sign", "%": "Percent", "=": "Equals"]

    private static let ops: Set<Character> = ["+", "−", "×", "÷"]

    private func press(_ key: String) {
        withAnimation(.snappy(duration: 0.15)) {
            switch key {
            case "AC":
                expr = ""
            case "⌫":
                if !expr.isEmpty { expr.removeLast() }
            case "=":
                if let v = Self.evaluate(expr) { expr = Self.plain(v); justEvaluated = true }
                return
            case "%":
                replaceLastNumber { $0 / 100 }
            case "±":
                replaceLastNumber { -$0 }
            case "+", "−", "×", "÷":
                guard !expr.isEmpty else { if key == "−" { expr = "-" }; break }
                if let last = expr.last, Self.ops.contains(last) { expr.removeLast() }
                if expr != "-" { expr.append(key) }
            case ".":
                if justEvaluated { expr = "" }
                let current = lastNumber
                if !current.contains(".") { expr += current.isEmpty || current == "-" ? "0." : "." }
            default:
                if justEvaluated { expr = "" }
                expr.append(key)
            }
            justEvaluated = false
        }
    }

    /// The number being typed (after the last operator).
    private var lastNumber: String {
        var s = ""
        for c in expr.reversed() {
            if Self.ops.contains(c) { break }
            s.insert(c, at: s.startIndex)
        }
        return s
    }

    private func replaceLastNumber(_ f: (Double) -> Double) {
        let n = lastNumber
        guard let v = Double(n) else { return }
        expr.removeLast(n.count)
        expr += Self.plain(f(v))
    }

    /// Reads "12+3×-4÷2": numbers may carry a leading "-" (from ±).
    static func evaluate(_ s: String) -> Double? {
        var nums: [Double] = []
        var opsOut: [Character] = []
        var current = ""
        for c in s {
            if ops.contains(c) {
                guard let v = Double(current) else { return nil }
                nums.append(v)
                opsOut.append(c)
                current = ""
            } else {
                current.append(c)
            }
        }
        if let v = Double(current) {
            nums.append(v)
        } else if !opsOut.isEmpty {
            opsOut.removeLast() // a trailing operator is ignored while typing
        } else {
            return nil
        }
        guard nums.count == opsOut.count + 1 else { return nil }
        // × and ÷ first.
        var terms: [Double] = [nums[0]]
        var addOps: [Character] = []
        for (i, op) in opsOut.enumerated() {
            let v = nums[i + 1]
            switch op {
            case "×": terms[terms.count - 1] *= v
            case "÷": terms[terms.count - 1] /= v
            default: terms.append(v); addOps.append(op)
            }
        }
        var total = terms[0]
        for (i, op) in addOps.enumerated() { total += op == "+" ? terms[i + 1] : -terms[i + 1] }
        return total.isFinite ? total : nil
    }

    /// For the display: grouped digits.
    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 8
        f.usesGroupingSeparator = true
        if abs(v) >= 1e15 || (abs(v) < 1e-8 && v != 0) {
            f.numberStyle = .scientific
            f.maximumFractionDigits = 6
        }
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// For typing on from: no grouping, "." as the decimal point.
    static func plain(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        var s = String(format: "%.10f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

// MARK: - Browser

/// A small web browser floating over the notes: drag its top bar to move it, the corner to resize it.
struct FloatingBrowser: View {
    let onClose: () -> Void
    @AppStorage("folio.browserURL") private var lastURL = "https://www.google.com"
    @StateObject private var web = WebModel()
    @State private var address = ""
    @State private var origin: CGPoint?
    @State private var dragFrom: CGPoint?
    @State private var size = CGSize(width: 440, height: 580)
    @State private var sizeFrom: CGSize?
    @FocusState private var addressFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            let o = clampedOrigin(origin ?? CGPoint(x: bounds.width - size.width - 24, y: 80), in: bounds)
            VStack(spacing: 0) {
                bar
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { v in
                            let from = dragFrom ?? o
                            if dragFrom == nil { dragFrom = o }
                            origin = clampedOrigin(CGPoint(x: from.x + v.translation.width, y: from.y + v.translation.height),
                                                   in: bounds)
                        }
                        .onEnded { _ in dragFrom = nil })
                ZStack(alignment: .top) {
                    WebView(model: web)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    if web.progress > 0, web.progress < 1 {
                        ProgressView(value: web.progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.action)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color(hex: "#1C1C1E"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) { resizeGrip(bounds: bounds, origin: o) }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .offset(x: o.x, y: o.y)
        }
        .onAppear {
            if web.webView.url == nil { web.load(lastURL) }
        }
        .onChange(of: web.url) { _, u in
            if let u {
                lastURL = u.absoluteString
                if !addressFocused { address = u.host() ?? u.absoluteString }
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 6) {
            iconButton("xmark", label: "Close Browser", action: onClose)
            iconButton("chevron.left", label: "Back", enabled: web.canGoBack) { web.webView.goBack() }
            iconButton("chevron.right", label: "Forward", enabled: web.canGoForward) { web.webView.goForward() }
            TextField("Search or enter website", text: $address)
                .focused($addressFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .onSubmit { web.load(address); addressFocused = false }
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.1)))
                .onChange(of: addressFocused) { _, f in
                    if f { address = web.url?.absoluteString ?? address }
                }
            iconButton(web.isLoading ? "xmark.circle" : "arrow.clockwise", label: web.isLoading ? "Stop" : "Reload") {
                if web.isLoading { web.webView.stopLoading() } else { web.webView.reload() }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(Color(hex: "#2C2C2E"))
        .contentShape(Rectangle())
    }

    private func iconButton(_ symbol: String, label: String, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func resizeGrip(bounds: CGSize, origin o: CGPoint) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .padding(6)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    let from = sizeFrom ?? size
                    if sizeFrom == nil { sizeFrom = size }
                    size = CGSize(width: min(max(from.width + v.translation.width, 300), bounds.width - o.x - 8),
                                  height: min(max(from.height + v.translation.height, 280), bounds.height - o.y - 8))
                }
                .onEnded { _ in sizeFrom = nil })
            .accessibilityLabel("Resize Browser")
    }

    private func clampedOrigin(_ p: CGPoint, in b: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, 8), max(8, b.width - size.width - 8)),
                y: min(max(p.y, 8), max(8, b.height - 60)))
    }
}

/// The web view and what the browser bar shows about it.
final class WebModel: NSObject, ObservableObject {
    let webView: WKWebView
    @Published var url: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    private var watches: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // The panel is phone-sized, so pages get their phone layout (the desktop layout overflowed it).
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        watches = [
            webView.observe(\.url, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.url = w.url } },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.canGoBack = w.canGoBack } },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.canGoForward = w.canGoForward } },
            webView.observe(\.isLoading, options: [.new]) { [weak self] w, _ in DispatchQueue.main.async { self?.isLoading = w.isLoading } },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
                DispatchQueue.main.async { self?.progress = w.estimatedProgress }
            }
        ]
    }

    /// A web address, or words to search for.
    func load(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var url: URL?
        if t.contains("://") {
            url = URL(string: t)
        } else if !t.contains(" "), t.contains("."), let u = URL(string: "https://" + t) {
            url = u
        }
        if url == nil {
            var c = URLComponents(string: "https://www.google.com/search")
            c?.queryItems = [URLQueryItem(name: "q", value: t)]
            url = c?.url
        }
        if let url { webView.load(URLRequest(url: url)) }
    }
}

private struct WebView: UIViewRepresentable {
    let model: WebModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
