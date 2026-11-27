import UIKit

/// A see-through ruler laid over the page. Lines started at either long edge run straight
/// along it. Moved and turned with fingers (the surface handles the gestures).
final class RulerView: UIView {
    var angle: CGFloat = 0 {
        didSet {
            transform = CGAffineTransform(rotationAngle: angle)
            var deg = Int((angle * 180 / .pi).rounded()) % 180
            if deg < 0 { deg += 180 }
            label.text = "\(deg)°"
        }
    }

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 1700, height: 88))
        isOpaque = false
        backgroundColor = UIColor(white: 0.12, alpha: 0.5)
        layer.cornerRadius = 10
        layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        layer.borderWidth = 1
        contentMode = .redraw
        label.text = "0°"
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.frame = CGRect(x: bounds.midX - 40, y: bounds.midY - 12, width: 80, height: 24)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1)
        var x: CGFloat = 10
        var i = 1
        while x < bounds.width - 4 {
            let long = i % 5 == 0
            let len: CGFloat = long ? 18 : 9
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: len))
            ctx.move(to: CGPoint(x: x, y: bounds.height)); ctx.addLine(to: CGPoint(x: x, y: bounds.height - len))
            x += 10
            i += 1
        }
        ctx.strokePath()
    }
}

/// The little bar above a lasso selection: change colour, duplicate, delete.
final class SelectionMenuView: UIView {
    var onColor: ((String) -> Void)?
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(hex: "#2C2C2E").withAlphaComponent(0.96)
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        addSubview(stack)

        let color = button("paintpalette", label: "Colour")
        let colors = Array(Theme.penColors.prefix(20))
        color.menu = UIMenu(title: "Colour", children: colors.map { hex in
            UIAction(title: hex, image: UIImage(systemName: "circle.fill")?
                .withTintColor(UIColor(hex: hex), renderingMode: .alwaysOriginal)) { [weak self] _ in
                self?.onColor?(hex)
            }
        })
        color.showsMenuAsPrimaryAction = true
        let dup = button("plus.square.on.square", label: "Duplicate")
        dup.addAction(UIAction { [weak self] _ in self?.onDuplicate?() }, for: .touchUpInside)
        let del = button("trash", label: "Delete")
        del.tintColor = UIColor(red: 1, green: 0.42, blue: 0.40, alpha: 1)
        del.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        [color, dup, del].forEach { stack.addArrangedSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func button(_ symbol: String, label: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        b.tintColor = .white
        b.accessibilityLabel = label
        b.widthAnchor.constraint(equalToConstant: 48).isActive = true
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return b
    }

    override var intrinsicContentSize: CGSize { CGSize(width: 3 * 48 + 2 * 2 + 16, height: 44) }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.frame = bounds.insetBy(dx: 8, dy: 0)
    }
}
