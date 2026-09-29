import AppKit
import QuartzCore

/// パネルの縁にしがみつく小人。パネルの子ウィンドウにして一緒に動かし、クリックは下へ通す。
/// 画像（Resources/kobito-cling.png、64pt）の x=53 が手の位置で、そこをパネルの縁に合わせる。
@MainActor
final class KobitoWindow: NSPanel {
    static let size: CGFloat = 64
    /// 画像の中の手の位置（左上を原点とした pt）。
    static let grip = CGPoint(x: 53, y: 21)

    private let imageLayer = CALayer()
    private var mirrored = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = NSView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        view.wantsLayer = true
        view.layer?.addSublayer(imageLayer)
        contentView = view
        imageLayer.contents = Self.image
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.shadowOpacity = 0.18
        imageLayer.shadowRadius = 2
        imageLayer.shadowOffset = CGSize(width: 0, height: -1)
        layout(mirrored: false)
    }

    override var canBecomeKey: Bool { false }

    static let image: NSImage? = Bundle.main.url(forResource: "kobito-cling", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    /// 手のところを軸にして、ゆっくり揺らす。左端のパネルでは左右を反転する。
    private func layout(mirrored: Bool) {
        self.mirrored = mirrored
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // CALayer は左下が原点。
        let anchor = CGPoint(x: (mirrored ? Self.size - Self.grip.x : Self.grip.x) / Self.size, y: 1 - Self.grip.y / Self.size)
        imageLayer.bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        imageLayer.anchorPoint = anchor
        imageLayer.position = CGPoint(x: anchor.x * Self.size, y: anchor.y * Self.size)
        imageLayer.transform = mirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        CATransaction.commit()
        imageLayer.removeAnimation(forKey: "sway")
        let sway = CABasicAnimation(keyPath: "transform.rotation.z")
        sway.fromValue = mirrored ? 0.07 : -0.07
        sway.toValue = mirrored ? -0.03 : 0.03
        sway.duration = 1.9
        sway.autoreverses = true
        sway.repeatCount = .infinity
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer.add(sway, forKey: "sway")
    }

    /// パネルの内側の縁（画面の中央寄り）の、上から4割ほどの所につかまらせる。
    func attach(to panelFrame: NSRect, edge: Settings.Edge) {
        let mirror = edge == .left
        if mirror != mirrored || imageLayer.animation(forKey: "sway") == nil { layout(mirrored: mirror) }
        let gripX = mirror ? Self.size - Self.grip.x : Self.grip.x
        let edgeX = mirror ? panelFrame.maxX : panelFrame.minX
        let gripY = panelFrame.maxY - panelFrame.height * 0.42
        setFrame(NSRect(x: edgeX - gripX, y: gripY - (Self.size - Self.grip.y), width: Self.size, height: Self.size), display: true)
    }
}
