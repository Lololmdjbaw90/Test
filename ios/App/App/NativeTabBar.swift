import UIKit
import Capacitor

// The app's screen: Capacitor's web view plus our native plugins.
class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(NativeTabBarPlugin())
    }
}

// A real iOS tab bar floating over the web view. On iOS 26 it's made of
// Liquid Glass (UIGlassEffect); on older iOS it falls back to a blur.
// The web app sends the tabs and listens for "select".
@objc(NativeTabBarPlugin)
public class NativeTabBarPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NativeTabBarPlugin"
    public let jsName = "NativeTabBar"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "show", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hide", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setSelected", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setBadges", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setDark", returnType: CAPPluginReturnPromise),
    ]
    private var bar: GlassTabBar?

    @objc func show(_ call: CAPPluginCall) {
        let raw = call.getArray("items", JSObject.self) ?? []
        let items = raw.map { obj in
            GlassTabBar.Item(
                id: obj["id"] as? String ?? "",
                title: obj["title"] as? String ?? "",
                icon: obj["icon"] as? String ?? "circle",
                accent: obj["accent"] as? Bool ?? false
            )
        }
        let selected = call.getString("selected")
        DispatchQueue.main.async {
            guard let host = self.bridge?.viewController?.view else {
                call.reject("No view")
                return
            }
            if self.bar == nil {
                let bar = GlassTabBar()
                bar.onSelect = { [weak self] id in self?.notifyListeners("select", data: ["id": id]) }
                bar.translatesAutoresizingMaskIntoConstraints = false
                host.addSubview(bar)
                let fill = bar.widthAnchor.constraint(equalTo: host.widthAnchor, constant: -24)
                fill.priority = .defaultHigh
                NSLayoutConstraint.activate([
                    bar.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                    fill,
                    bar.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
                    bar.heightAnchor.constraint(equalToConstant: 62),
                    bar.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -6),
                ])
                self.bar = bar
            }
            self.bar?.setItems(items, selected: selected)
            self.bar?.setVisible(true)
            call.resolve()
        }
    }

    @objc func hide(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.bar?.setVisible(false)
            call.resolve()
        }
    }

    @objc func setSelected(_ call: CAPPluginCall) {
        let id = call.getString("id")
        DispatchQueue.main.async {
            self.bar?.select(id, animated: true)
            call.resolve()
        }
    }

    @objc func setBadges(_ call: CAPPluginCall) {
        var counts: [String: Int] = [:]
        for (key, value) in call.getObject("badges") ?? [:] {
            if let n = value as? Int { counts[key] = n } else if let n = value as? Double { counts[key] = Int(n) }
        }
        DispatchQueue.main.async {
            self.bar?.setBadges(counts)
            call.resolve()
        }
    }

    @objc func setDark(_ call: CAPPluginCall) {
        let dark = call.getBool("dark") ?? false
        DispatchQueue.main.async {
            self.bar?.overrideUserInterfaceStyle = dark ? .dark : .unspecified
            call.resolve()
        }
    }
}

final class GlassTabBar: UIView {
    struct Item {
        let id: String
        let title: String
        let icon: String
        let accent: Bool
    }

    var onSelect: ((String) -> Void)?
    private let background = UIVisualEffectView(effect: GlassTabBar.glassEffect())
    private let lens = UIView()
    private let stack = UIStackView()
    private var buttons: [String: UIButton] = [:]
    private var badgeLabels: [String: UILabel] = [:]
    private var accentIds: Set<String> = []
    private var selectedId: String?
    private let pink = UIColor(red: 1.0, green: 0.30, blue: 0.49, alpha: 1.0)
    private let haptic = UISelectionFeedbackGenerator()

    static func glassEffect() -> UIVisualEffect {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            return glass
        }
        #endif
        return UIBlurEffect(style: .systemChromeMaterial)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

        addSubview(background)
        lens.isUserInteractionEnabled = false
        lens.backgroundColor = UIColor.label.withAlphaComponent(0.08)
        lens.layer.cornerCurve = .continuous
        background.contentView.addSubview(lens)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: background.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        roundCorners(background, radius: bounds.height / 2)
        placeLens(animated: false)
    }

    private func roundCorners(_ view: UIView, radius: CGFloat) {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            view.cornerConfiguration = .capsule()
            return
        }
        #endif
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
    }

    func setItems(_ items: [Item], selected: String?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = [:]
        badgeLabels = [:]
        accentIds = Set(items.filter { $0.accent }.map { $0.id })
        for item in items {
            let button = makeButton(item)
            stack.addArrangedSubview(button)
            buttons[item.id] = button
        }
        selectedId = selected
        layoutIfNeeded()
        select(selected, animated: false)
    }

    private func makeButton(_ item: Item) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = item.title.isEmpty ? "Create" : item.title
        button.accessibilityIdentifier = item.id
        if item.accent {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = pink
            config.baseForegroundColor = .white
            config.cornerStyle = .capsule
            config.image = UIImage(systemName: item.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold))
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            button.configuration = config
        } else {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: item.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
            config.imagePlacement = .top
            config.imagePadding = 3
            var title = AttributedString(item.title)
            title.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            config.attributedTitle = title
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
            button.configuration = config
            button.tintColor = .secondaryLabel

            let badge = UILabel()
            badge.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            badge.textColor = .white
            badge.textAlignment = .center
            badge.backgroundColor = pink
            badge.layer.cornerRadius = 8
            badge.clipsToBounds = true
            badge.isHidden = true
            badge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.heightAnchor.constraint(equalToConstant: 16),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
                badge.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 13),
                badge.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
            ])
            badgeLabels[item.id] = badge
        }
        button.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.haptic.selectionChanged()
            if !item.accent { self.select(item.id, animated: true) }
            self.onSelect?(item.id)
        }, for: .touchUpInside)
        return button
    }

    func select(_ id: String?, animated: Bool) {
        selectedId = id
        for (key, button) in buttons where !accentIds.contains(key) {
            button.tintColor = key == id ? pink : .secondaryLabel
        }
        placeLens(animated: animated)
    }

    private func placeLens(animated: Bool) {
        guard let id = selectedId, let button = buttons[id], button.bounds.width > 0 else {
            lens.alpha = 0
            return
        }
        let frame = button.convert(button.bounds, to: background.contentView).insetBy(dx: 2, dy: 5)
        let apply = {
            self.lens.alpha = 1
            self.lens.frame = frame
            self.lens.layer.cornerRadius = frame.height / 2
        }
        if animated {
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.4, options: [.allowUserInteraction, .beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
    }

    func setBadges(_ counts: [String: Int]) {
        for (id, label) in badgeLabels {
            let n = counts[id] ?? 0
            label.isHidden = n <= 0
            label.text = n > 9 ? " 9+ " : " \(n) "
        }
    }

    private var visibilityRevision = 0

    func setVisible(_ visible: Bool) {
        visibilityRevision += 1
        let revision = visibilityRevision
        if visible { isHidden = false }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState], animations: {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 24)
        }, completion: { _ in
            if !visible && self.visibilityRevision == revision { self.isHidden = true }
        })
    }
}
