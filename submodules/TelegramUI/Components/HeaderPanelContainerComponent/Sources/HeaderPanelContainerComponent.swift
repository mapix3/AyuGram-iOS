import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramPresentationData
import GlassBackgroundComponent
import ComponentDisplayAdapters

public protocol HeaderPanelContainerChildView: UIView {
    func setOverlayContainerView(overlayContainerView: UIView)
}

public final class HeaderPanelContainerComponent: Component {
    public final class Panel: Equatable {
        public let key: AnyHashable
        public let orderIndex: Int
        public let component: AnyComponent<Empty>
        
        public init(key: AnyHashable, orderIndex: Int, component: AnyComponent<Empty>) {
            self.key = key
            self.orderIndex = orderIndex
            self.component = component
        }
        
        public static func ==(lhs: Panel, rhs: Panel) -> Bool {
            if lhs.key != rhs.key {
                return false
            }
            if lhs.orderIndex != rhs.orderIndex {
                return false
            }
            if lhs.component != rhs.component {
                return false
            }
            return true
        }
    }
    
    public struct ClassicLayout: Equatable {
        public var leftInset: CGFloat
        public var rightInset: CGFloat
        
        public init(leftInset: CGFloat, rightInset: CGFloat) {
            self.leftInset = leftInset
            self.rightInset = rightInset
        }
    }
    
    public let theme: PresentationTheme
    public let preferClearGlass: Bool
    public let classicLayout: ClassicLayout?
    public let tabs: AnyComponent<Empty>?
    public let panels: [Panel]
    
    public init(
        theme: PresentationTheme,
        preferClearGlass: Bool = false,
        classicLayout: ClassicLayout? = nil,
        tabs: AnyComponent<Empty>?,
        panels: [Panel]
    ) {
        self.theme = theme
        self.preferClearGlass = preferClearGlass
        self.classicLayout = classicLayout
        self.tabs = tabs
        self.panels = panels
    }
    
    public static func ==(lhs: HeaderPanelContainerComponent, rhs: HeaderPanelContainerComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.preferClearGlass != rhs.preferClearGlass {
            return false
        }
        if lhs.classicLayout != rhs.classicLayout {
            return false
        }
        if lhs.tabs != rhs.tabs {
            return false
        }
        if lhs.panels != rhs.panels {
            return false
        }
        return true
    }
    
    private final class PanelItemView: UIView {
        let view = ComponentView<Empty>()
        let separator = SimpleLayer()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    public final class View: UIView {
        private let backgroundContainer: GlassBackgroundContainerView
        private let backgroundView: GlassBackgroundView
        private let contentContainer: UIView
        
        private var tabsView: ComponentView<Empty>?
        private var classicBackground: NavigationBackgroundNode?
        private var classicBottomSeparator: SimpleLayer?
        private var panelViews: [AnyHashable: PanelItemView] = [:]
        
        private var component: HeaderPanelContainerComponent?
        private weak var state: EmptyComponentState?
        
        public var tabs: UIView? {
            return self.tabsView?.view
        }
        
        public func panel(forKey key: AnyHashable) -> UIView? {
            return self.panelViews[key]?.view.view
        }
        
        override init(frame: CGRect) {
            self.backgroundContainer = GlassBackgroundContainerView()
            self.backgroundView = GlassBackgroundView()
            self.contentContainer = UIView()
            self.contentContainer.clipsToBounds = true
            
            super.init(frame: frame)
            
            self.backgroundContainer.contentView.addSubview(self.backgroundView)
            self.addSubview(self.backgroundContainer)
            
            self.backgroundView.contentView.addSubview(self.contentContainer)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(component: HeaderPanelContainerComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            if let classicLayout = component.classicLayout {
                return self.updateClassic(component: component, classicLayout: classicLayout, availableSize: availableSize, state: state, transition: transition)
            }
            var isAnimatingReplacement = false
            if let previousComponent = self.component {
                isAnimatingReplacement = !component.panels.contains(where: { panel in previousComponent.panels.contains(where: { $0.key == panel.key }) })
            }
            
            self.component = component
            self.state = state
            
            let sideInset: CGFloat = 16.0
            
            var size = CGSize(width: availableSize.width, height: 0.0)
            
            var isFirstPanel = true
            
            if let tabs = component.tabs {
                let tabsView: ComponentView<Empty>
                var tabsTransition = transition
                if let current = self.tabsView {
                    tabsView = current
                } else {
                    tabsTransition = tabsTransition.withAnimation(.none)
                    tabsView = ComponentView()
                    self.tabsView = tabsView
                }
                let tabsSize = tabsView.update(
                    transition: tabsTransition,
                    component: tabs,
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 40.0)
                )
                let tabsFrame = CGRect(origin: CGPoint(x: 0.0, y: size.height), size: tabsSize)
                if let tabsComponentView = tabsView.view {
                    if tabsComponentView.superview == nil {
                        self.contentContainer.addSubview(tabsComponentView)
                        if let tabsComponentView = tabsComponentView as? HeaderPanelContainerChildView {
                            tabsComponentView.setOverlayContainerView(overlayContainerView: self.backgroundContainer.contentView)
                        }
                        transition.animateAlpha(view: tabsComponentView, from: 0.0, to: 1.0)
                    }
                    tabsTransition.setFrame(view: tabsComponentView, frame: tabsFrame)
                }
                size.height += tabsSize.height
                isFirstPanel = false
            } else if let tabsView = self.tabsView {
                self.tabsView = nil
                if let tabsComponentView = tabsView.view {
                    transition.setAlpha(view: tabsComponentView, alpha: 0.0, completion: { [weak tabsComponentView] _ in
                        tabsComponentView?.removeFromSuperview()
                    })
                }
            }
            
            var validPanelKeys: [AnyHashable] = []
            for panel in component.panels {
                validPanelKeys.append(panel.key)
                
                var panelTransition = transition
                let panelView: PanelItemView
                if let current = self.panelViews[panel.key] {
                    panelView = current
                } else {
                    panelTransition = panelTransition.withAnimation(.none)
                    panelView = PanelItemView()
                    self.panelViews[panel.key] = panelView
                    self.contentContainer.layer.insertSublayer(panelView.separator, at: 0)
                    self.contentContainer.addSubview(panelView)
                }
                
                let panelSize = panelView.view.update(
                    transition: panelTransition,
                    component: panel.component,
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 10000.0)
                )
                let panelFrame = CGRect(origin: CGPoint(x: 0.0, y: size.height), size: panelSize)
                if let panelComponentView = panelView.view.view {
                    if panelComponentView.superview == nil {
                        panelView.addSubview(panelComponentView)
                        transition.animateAlpha(view: panelView, from: 0.0, to: 1.0)
                        panelView.separator.opacity = 0.0
                        panelView.clipsToBounds = true
                        if isAnimatingReplacement {
                            panelView.frame = panelFrame
                        } else {
                            panelView.frame = CGRect(origin: panelFrame.origin, size: CGSize(width: panelFrame.width, height: 0.0))
                        }
                    }
                    
                    panelView.separator.backgroundColor = component.theme.list.itemPlainSeparatorColor.cgColor
                    
                    let isFrameUpdated = panelComponentView.frame != panelFrame
                    transition.setFrame(view: panelView, frame: panelFrame, completion: { [weak panelView] completed in
                        if let panelView, completed, isFrameUpdated {
                            panelView.clipsToBounds = false
                        }
                    })
                    panelTransition.setFrame(view: panelComponentView, frame: CGRect(origin: CGPoint(), size: panelFrame.size))
                    panelTransition.setFrame(layer: panelView.separator, frame: CGRect(origin: panelFrame.origin, size: CGSize(width: panelFrame.width, height: UIScreenPixel)))
                    
                    transition.setAlpha(layer: panelView.separator, alpha: isFirstPanel ? 0.0 : 1.0)
                }
                size.height += panelSize.height
                isFirstPanel = false
            }
            
            var removedPanelKeys: [AnyHashable] = []
            for (key, panelView) in self.panelViews {
                if !validPanelKeys.contains(key) {
                    removedPanelKeys.append(key)
                    transition.setAlpha(view: panelView, alpha: 0.0, completion: { [weak panelView] _ in
                        panelView?.removeFromSuperview()
                    })
                    let separator = panelView.separator
                    transition.setAlpha(layer: separator, alpha: 0.0, completion: { [weak separator] _ in
                        separator?.removeFromSuperlayer()
                    })
                    if !isAnimatingReplacement {
                        panelView.clipsToBounds = true
                        transition.setFrame(view: panelView, frame: CGRect(origin: panelView.frame.origin, size: CGSize(width: panelView.bounds.width, height: 0.0)))
                    }
                }
            }
            for key in removedPanelKeys {
                self.panelViews.removeValue(forKey: key)
            }
            
            let backgroundSize = CGSize(width: size.width, height: max(40.0, size.height))
            
            transition.setFrame(view: self.backgroundContainer, frame: CGRect(origin: CGPoint(), size: backgroundSize).insetBy(dx: -32.0, dy: -32.0))
            self.backgroundContainer.update(size: CGSize(width: backgroundSize.width + 32.0 * 2.0, height: backgroundSize.height + 32.0 * 2.0), isDark: component.theme.overallDarkAppearance, transition: transition)
            
            let backgroundFrame = CGRect(origin: CGPoint(x: 32.0 + sideInset, y: 32.0), size: CGSize(width: size.width - sideInset * 2.0, height: backgroundSize.height))
            
            var panelCount = 0
            if component.tabs != nil {
                panelCount += 1
            }
            panelCount += component.panels.count
            var cornerRadius: CGFloat = 0.0
            if panelCount == 1 && backgroundFrame.height <= 50.0 {
                cornerRadius = backgroundFrame.height * 0.5
            } else {
                cornerRadius = 20.0
            }
            
            transition.setFrame(view: self.backgroundView, frame: backgroundFrame)
            self.backgroundView.update(size: backgroundFrame.size, cornerRadius: cornerRadius, isDark: component.theme.overallDarkAppearance, tintColor: .init(kind: component.preferClearGlass ? .clear : .panel), isInteractive: true, transition: transition)
            
            transition.setAlpha(view: self.backgroundContainer, alpha: (component.tabs != nil || !component.panels.isEmpty) ? 1.0 : 0.0)
            
            transition.setFrame(view: self.contentContainer, frame: CGRect(origin: CGPoint(), size: backgroundFrame.size))
            
            transition.setCornerRadius(layer: self.contentContainer.layer, cornerRadius: min(cornerRadius, backgroundFrame.height * 0.5))
            
            return size
        }
        
        private func updateClassic(component: HeaderPanelContainerComponent, classicLayout: ClassicLayout, availableSize: CGSize, state: EmptyComponentState, transition: ComponentTransition) -> CGSize {
            var isAnimatingReplacement = false
            if let previousComponent = self.component {
                isAnimatingReplacement = !component.panels.contains(where: { panel in previousComponent.panels.contains(where: { $0.key == panel.key }) })
            }
            
            self.component = component
            self.state = state
            
            self.backgroundContainer.isHidden = true
            if self.contentContainer.superview !== self {
                self.contentContainer.removeFromSuperview()
                self.addSubview(self.contentContainer)
            }
            
            let backgroundColor = component.theme.rootController.navigationBar.blurredBackgroundColor
            let classicBackground: NavigationBackgroundNode
            if let current = self.classicBackground {
                classicBackground = current
                classicBackground.updateColor(color: backgroundColor, transition: .immediate)
            } else {
                classicBackground = NavigationBackgroundNode(color: backgroundColor)
                classicBackground.isUserInteractionEnabled = false
                self.classicBackground = classicBackground
                self.insertSubview(classicBackground.view, at: 0)
            }
            
            let classicBottomSeparator: SimpleLayer
            if let current = self.classicBottomSeparator {
                classicBottomSeparator = current
            } else {
                classicBottomSeparator = SimpleLayer()
                self.classicBottomSeparator = classicBottomSeparator
                self.layer.addSublayer(classicBottomSeparator)
            }
            
            let separatorColor = component.theme.rootController.navigationBar.separatorColor
            let contentWidth = max(0.0, availableSize.width - classicLayout.leftInset - classicLayout.rightInset)
            
            var size = CGSize(width: availableSize.width, height: 0.0)
            
            if let tabs = component.tabs {
                let tabsView: ComponentView<Empty>
                var tabsTransition = transition
                if let current = self.tabsView {
                    tabsView = current
                } else {
                    tabsTransition = tabsTransition.withAnimation(.none)
                    tabsView = ComponentView()
                    self.tabsView = tabsView
                }
                let tabsSize = tabsView.update(
                    transition: tabsTransition,
                    component: tabs,
                    environment: {},
                    containerSize: CGSize(width: contentWidth, height: 40.0)
                )
                let tabsFrame = CGRect(origin: CGPoint(x: classicLayout.leftInset, y: size.height), size: tabsSize)
                if let tabsComponentView = tabsView.view {
                    if tabsComponentView.superview == nil {
                        self.contentContainer.addSubview(tabsComponentView)
                        if let tabsComponentView = tabsComponentView as? HeaderPanelContainerChildView {
                            tabsComponentView.setOverlayContainerView(overlayContainerView: self)
                        }
                        transition.animateAlpha(view: tabsComponentView, from: 0.0, to: 1.0)
                    }
                    tabsTransition.setFrame(view: tabsComponentView, frame: tabsFrame)
                }
                size.height += tabsSize.height
            } else if let tabsView = self.tabsView {
                self.tabsView = nil
                if let tabsComponentView = tabsView.view {
                    transition.setAlpha(view: tabsComponentView, alpha: 0.0, completion: { [weak tabsComponentView] _ in
                        tabsComponentView?.removeFromSuperview()
                    })
                }
            }
            
            var validPanelKeys: [AnyHashable] = []
            for panel in component.panels {
                validPanelKeys.append(panel.key)
                
                var panelTransition = transition
                let panelView: PanelItemView
                if let current = self.panelViews[panel.key] {
                    panelView = current
                } else {
                    panelTransition = panelTransition.withAnimation(.none)
                    panelView = PanelItemView()
                    self.panelViews[panel.key] = panelView
                    self.contentContainer.addSubview(panelView)
                    self.contentContainer.layer.addSublayer(panelView.separator)
                }
                
                let panelSize = panelView.view.update(
                    transition: panelTransition,
                    component: panel.component,
                    environment: {},
                    containerSize: CGSize(width: contentWidth, height: 10000.0)
                )
                let panelFrame = CGRect(origin: CGPoint(x: classicLayout.leftInset, y: size.height), size: panelSize)
                if let panelComponentView = panelView.view.view {
                    if panelComponentView.superview == nil {
                        panelView.addSubview(panelComponentView)
                        transition.animateAlpha(view: panelView, from: 0.0, to: 1.0)
                        panelView.separator.opacity = 0.0
                        panelView.clipsToBounds = true
                        if isAnimatingReplacement {
                            panelView.frame = panelFrame
                        } else {
                            panelView.frame = CGRect(origin: panelFrame.origin, size: CGSize(width: panelFrame.width, height: 0.0))
                        }
                    }
                    
                    panelView.separator.backgroundColor = separatorColor.cgColor
                    
                    let isFrameUpdated = panelComponentView.frame != panelFrame
                    transition.setFrame(view: panelView, frame: panelFrame, completion: { [weak panelView] completed in
                        if let panelView, completed, isFrameUpdated {
                            panelView.clipsToBounds = false
                        }
                    })
                    panelTransition.setFrame(view: panelComponentView, frame: CGRect(origin: CGPoint(), size: panelFrame.size))
                    panelTransition.setFrame(layer: panelView.separator, frame: CGRect(origin: CGPoint(x: 0.0, y: panelFrame.minY), size: CGSize(width: availableSize.width, height: UIScreenPixel)))
                    
                    transition.setAlpha(layer: panelView.separator, alpha: 1.0)
                }
                size.height += panelSize.height
            }
            
            var removedPanelKeys: [AnyHashable] = []
            for (key, panelView) in self.panelViews {
                if !validPanelKeys.contains(key) {
                    removedPanelKeys.append(key)
                    transition.setAlpha(view: panelView, alpha: 0.0, completion: { [weak panelView] _ in
                        panelView?.removeFromSuperview()
                    })
                    let separator = panelView.separator
                    transition.setAlpha(layer: separator, alpha: 0.0, completion: { [weak separator] _ in
                        separator?.removeFromSuperlayer()
                    })
                    if !isAnimatingReplacement {
                        panelView.clipsToBounds = true
                        transition.setFrame(view: panelView, frame: CGRect(origin: panelView.frame.origin, size: CGSize(width: panelView.bounds.width, height: 0.0)))
                    }
                }
            }
            for key in removedPanelKeys {
                self.panelViews.removeValue(forKey: key)
            }
            
            let hasContent = component.tabs != nil || !component.panels.isEmpty
            let backgroundFrame = CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: size.height))
            
            transition.setFrame(view: classicBackground.view, frame: backgroundFrame)
            classicBackground.update(size: backgroundFrame.size, cornerRadius: 0.0, transition: transition.containedViewLayoutTransition)
            transition.setAlpha(view: classicBackground.view, alpha: hasContent ? 1.0 : 0.0)
            
            classicBottomSeparator.backgroundColor = separatorColor.cgColor
            transition.setFrame(layer: classicBottomSeparator, frame: CGRect(origin: CGPoint(x: 0.0, y: size.height), size: CGSize(width: availableSize.width, height: UIScreenPixel)))
            transition.setAlpha(layer: classicBottomSeparator, alpha: hasContent ? 1.0 : 0.0)
            
            self.contentContainer.clipsToBounds = true
            transition.setFrame(view: self.contentContainer, frame: backgroundFrame)
            transition.setCornerRadius(layer: self.contentContainer.layer, cornerRadius: 0.0)
            
            return CGSize(width: availableSize.width, height: size.height)
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
