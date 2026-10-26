import UIKit
import UniformTypeIdentifiers

/// System paste control grants access for this explicit tap. The small fallback
/// explains Full Access without inspecting the user's clipboard.
final class BufferPasteButton: UIControl {
    private let native: UIPasteControl
    private let access = UIButton(type: .system)
    var onPaste: (([NSItemProvider]) -> Void)?
    var onNeedsAccess: (() -> Void)?
    var fullAccess = false { didSet { native.isHidden = !fullAccess; access.isHidden = fullAccess } }
    override var isEnabled: Bool { didSet { isUserInteractionEnabled = isEnabled; alpha = isEnabled ? 1 : 0.45 } }
    /// The control's opaque background must not cover the input line's outline.
    static let lineInset: CGFloat = 3
    var controlFrame: CGRect { native.frame }
    func setPurpose(label: String, hint: String) {
        native.accessibilityLabel = label; access.accessibilityLabel = label
        native.accessibilityHint = hint; access.accessibilityHint = hint
    }

    override init(frame: CGRect) {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.baseBackgroundColor = .systemBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = 5
        native = UIPasteControl(configuration: configuration)
        super.init(frame: frame)
        accessibilityIdentifier = "keyboard.buffer.paste"
        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.text.identifier])
        native.target = self; native.isHidden = true
        native.accessibilityLabel = L("粘贴剪贴板文字", "Paste clipboard text")
        native.accessibilityHint = L("插入 Buffer 当前光标位置", "Insert at the Buffer cursor")
        access.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        access.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .regular), forImageIn: .normal)
        access.accessibilityLabel = native.accessibilityLabel
        access.addAction(UIAction { [weak self] _ in self?.onNeedsAccess?() }, for: .touchUpInside)
        addSubview(native); addSubview(access)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        fullAccess && isEnabled && itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
    }
    override func paste(itemProviders: [NSItemProvider]) {
        guard fullAccess, isEnabled else { return }
        onPaste?(itemProviders)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Below its intrinsic size UIPasteControl can render an empty, inert
        // slot. Keep its native layout size and scale it into the input line,
        // clear of that line's border and rounded corners.
        let intrinsic = native.intrinsicContentSize
        let size = CGSize(width: max(44, ceil(intrinsic.width)), height: max(36, ceil(intrinsic.height)))
        let fit = bounds.insetBy(dx: Self.lineInset, dy: Self.lineInset)
        let scale = max(0, min(1, fit.width / size.width, fit.height / size.height))
        native.bounds = CGRect(origin: .zero, size: size)
        native.center = CGPoint(x: bounds.midX, y: bounds.midY)
        native.transform = CGAffineTransform(scaleX: scale, y: scale)
        access.frame = bounds
    }
}
