import AppKit
import ImageIO

struct SpriteRecord: Decodable {
    let file: String
    let pixelSize: [Int]
    let rect: [Double]
    let contentBounds: [Double]
    let registrationFeet: [Double]?
    static func bounds(_ values: [Double]) -> NSRect {
        NSRect(x:values[0],y:values[1],width:values[2],height:values[3])
    }
}

struct SpriteManifest: Decodable {
    let version: Int
    let canvas: [Int]
    let frames: [String:[SpriteRecord]]
}

struct SpriteFrame {
    let image: NSImage
    let bitmap: NSBitmapImageRep
    let rect: NSRect
    let contentBounds: NSRect
    let registrationFeet: NSRect?
    init(_ cg: CGImage, record: SpriteRecord) {
        // Keep original pixels; AppKit scales directly into the Retina backing store.
        image = NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
        bitmap = NSBitmapImageRep(cgImage:cg)
        rect = SpriteRecord.bounds(record.rect)
        contentBounds = SpriteRecord.bounds(record.contentBounds)
        registrationFeet = record.registrationFeet.map(SpriteRecord.bounds)
    }
    func contains(_ p: NSPoint) -> Bool {
        guard rect.contains(p) else { return false }
        let x=min(bitmap.pixelsWide-1,Int((p.x-rect.minX)/rect.width*CGFloat(bitmap.pixelsWide)))
        let y=min(bitmap.pixelsHigh-1,Int((p.y-rect.minY)/rect.height*CGFloat(bitmap.pixelsHigh)))
        return (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.10
    }
    func opaqueBounds() -> NSRect { contentBounds }
    func draw(in canvas: NSRect) {
        let destination=NSRect(x:canvas.minX+rect.minX*canvas.width/192,
                               y:canvas.minY+rect.minY*canvas.height/208,
                               width:rect.width*canvas.width/192,height:rect.height*canvas.height/208)
        image.draw(in:destination,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
}

final class SpriteStore {
    var frames: [String:[SpriteFrame]] = [:]
    var peekBounds: [String:NSRect] = [:]
    init(resources: URL) throws {
        let directory=resources.appendingPathComponent("HighResolution")
        for filename in ["manifest.json","dizzy.json"] {
            let manifest=try JSONDecoder().decode(SpriteManifest.self,
                         from:Data(contentsOf:directory.appendingPathComponent(filename)))
            guard manifest.version == 1 && manifest.canvas == [192,208] else {
                throw NSError(domain:"BlueWhalePet",code:2,userInfo:[NSLocalizedDescriptionKey:"高清素材配置不正确"])
            }
            for (name,records) in manifest.frames {
                guard frames[name] == nil else { throw NSError(domain:"BlueWhalePet",code:11) }
                frames[name]=try records.map { record in
                    let url=directory.appendingPathComponent(record.file)
                    guard record.rect.count == 4 && record.contentBounds.count == 4 && record.pixelSize.count == 2,
                          record.rect.allSatisfy({ $0.isFinite }),record.rect[2]>0,record.rect[3]>0,
                          record.registrationFeet == nil || record.registrationFeet!.count == 4,
                          let source=CGImageSourceCreateWithURL(url as CFURL,nil),
                          let image=CGImageSourceCreateImageAtIndex(source,0,nil),
                          [image.width,image.height] == record.pixelSize else {
                        throw NSError(domain:"BlueWhalePet",code:3,userInfo:[NSLocalizedDescriptionKey:"无法读取高清动画素材：\(record.file)"])
                    }
                    return SpriteFrame(image,record:record)
                }
            }
        }
        for name in ["peek-left","peek-right"] {
            guard let sequence=frames[name],sequence.count == 2 else {
                throw NSError(domain:"BlueWhalePet",code:7,userInfo:[NSLocalizedDescriptionKey:"缺少探头动画"])
            }
            peekBounds[name]=sequence.reduce(NSRect.null) { $0.union($1.opaqueBounds()) }
        }
    }
}

final class PetPanel: NSPanel {
    var allowsTransparentOverflow=false
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        allowsTransparentOverflow ? frameRect : super.constrainFrameRect(frameRect,to:screen)
    }
}

final class PetView: NSView {
    weak var controller: PetController?
    var sprite: SpriteFrame? { didSet { needsDisplay = true } }
    var dizzyElapsed: Double? { didSet { needsDisplay = true } }
    var pressed = false
    private var pressMouse = NSPoint.zero
    private var pressOrigin = NSPoint.zero
    private var dragged = false
    private var pressedWhilePeeking = false
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        guard let elapsed=dizzyElapsed else {
            sprite?.draw(in:bounds)
            return
        }
        drawDizzyOrbit(elapsed:elapsed,front:false)
        NSGraphicsContext.saveGraphicsState()
        var transform=AffineTransform()
        let pivot=NSPoint(x:bounds.width/2,y:202*bounds.height/208)
        let strength=min(1,elapsed/0.2)*min(1,max(0,(5-elapsed)/0.6))
        transform.translate(x:pivot.x,y:pivot.y)
        transform.rotate(byDegrees:sin(elapsed*2*Double.pi/1.3)*1.8*strength)
        transform.translate(x:-pivot.x,y:-pivot.y)
        (transform as NSAffineTransform).concat()
        sprite?.draw(in:bounds)
        NSGraphicsContext.restoreGraphicsState()
        drawDizzyOrbit(elapsed:elapsed,front:true)
    }

    private func drawDizzyOrbit(elapsed: Double, front: Bool) {
        let sx=bounds.width/192, sy=bounds.height/208
        let opacity=min(1,elapsed/0.15)*min(1,max(0,(5-elapsed)/0.5))
        for index in 0..<5 {
            let angle=elapsed*2*Double.pi/1.4+Double(index)*2*Double.pi/5
            guard (sin(angle)>=0) == front else { continue }
            let x=(89+38*cos(angle))*sx, y=(85+9*sin(angle))*sy
            let radius=(3.8+0.8*sin(elapsed*7+Double(index)))*sx
            let star=NSBezierPath()
            for point in 0..<8 {
                let a=Double(point)*Double.pi/4-Double.pi/2
                let r=point%2 == 0 ? radius : radius*0.28
                let p=NSPoint(x:x+cos(a)*r,y:y+sin(a)*r)
                if point == 0 { star.move(to:p) } else { star.line(to:p) }
            }
            star.close()
            NSColor(calibratedRed:1,green:0.88,blue:0.3,alpha:opacity).setFill()
            star.fill()
            NSColor(calibratedRed:0.74,green:0.49,blue:0.12,alpha:opacity*0.8).setStroke()
            star.lineWidth=0.55*sx
            star.stroke()
        }
    }
    func sourcePoint(_ local: NSPoint) -> NSPoint {
        NSPoint(x: local.x * 192 / bounds.width, y: local.y * 208 / bounds.height)
    }
    func isHead(_ p: NSPoint) -> Bool {
        let x = (p.x - 89) / 41
        let y = (p.y - (dizzyElapsed == nil ? 80 : 136)) / (dizzyElapsed == nil ? 34 : 28)
        return x*x + y*y < 1
    }
    func isBowl(_ p: NSPoint) -> Bool {
        let rect=dizzyElapsed == nil ? NSRect(x:65,y:111,width:58,height:38) : NSRect(x:71,y:157,width:45,height:27)
        return rect.contains(p)
    }
    override func mouseDown(with event: NSEvent) {
        pressedWhilePeeking = controller?.model.motion.isPeeking ?? false
        controller?.prepareForPress(revealPeek:!pressedWhilePeeking)
        pressed = true
        dragged = false
        pressMouse = NSEvent.mouseLocation
        pressOrigin = window?.frame.origin ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - pressMouse.x, dy = mouse.y - pressMouse.y
        if !dragged && hypot(dx, dy) > 4 {
            dragged = true
            if !pressedWhilePeeking { controller?.act(.idle) }
        }
        if dragged {
            let origin=NSPoint(x:pressOrigin.x+dx,y:pressOrigin.y+dy)
            if pressedWhilePeeking { controller?.dragPeek(to:origin) }
            else { window?.setFrameOrigin(origin) }
        }
    }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if dragged {
            if !pressedWhilePeeking { controller?.keepOnScreen(allowPeeking:true) }
            controller?.savePosition()
            return
        }
        let p = sourcePoint(convert(event.locationInWindow, from: nil))
        if pressedWhilePeeking { controller?.act(.idle) }
        else if controller?.model.motion == .sleeping { controller?.act(.idle) }
        else if isBowl(p) { controller?.act(.eating) }
        else if isHead(p) { controller?.act(.headpat) }
        else { controller?.act(.waving) }
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class PetController: NSObject, NSMenuDelegate {
    let panel: PetPanel
    let view: PetView
    let sprites: SpriteStore
    var model = PetModel(now: ProcessInfo.processInfo.systemUptime)
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastMouse = NSEvent.mouseLocation
    private var lastHeadpat = -Double.infinity
    private var scale: CGFloat = 1.25
    private var pinned = true
    private let defaults: UserDefaults
    private var menuOpen = false
    private var dockArea: NSRect?
    private var dockVisibleArea: NSRect?
    private var dockStart: Double = 0
    private var dockOrigin = NSPoint.zero

    init(resources: URL, testing: Bool = false) throws {
        defaults = testing ? UserDefaults(suiteName:"local.bluewhale.desktop.pet.smoke")! : .standard
        if testing { defaults.removePersistentDomain(forName:"local.bluewhale.desktop.pet.smoke") }
        sprites = try SpriteStore(resources: resources)
        view = PetView(frame: NSRect(x: 0, y: 0, width: 240, height: 260))
        panel = PetPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()
        view.controller = self
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        if defaults.object(forKey: "automaticWalking") != nil {
            model.automaticWalking = defaults.bool(forKey: "automaticWalking")
        }
        if defaults.object(forKey:"occasionalAffection") != nil { model.occasionalAffection=defaults.bool(forKey:"occasionalAffection") }
        if defaults.object(forKey:"mouseChasing") != nil { model.mouseChasing=defaults.bool(forKey:"mouseChasing") }
        if defaults.object(forKey:"edgePeeking") != nil { model.edgePeeking=defaults.bool(forKey:"edgePeeking") }
        let savedScale = defaults.double(forKey: "petScale")
        scale = [1.0, 1.25, 1.6].contains(savedScale) ? savedScale : 1.25
        panel.setContentSize(NSSize(width: 192*scale, height: 208*scale))
        if defaults.object(forKey: "petX") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "petX"), y: defaults.double(forKey: "petY")))
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX-panel.frame.width-40,
                                         y: screen.visibleFrame.minY+12))
        }
        keepOnScreen()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menuIcon=NSImage(contentsOf:resources.appendingPathComponent("DeepSeekStatus.pdf"))
        menuIcon?.size=NSSize(width:22,height:17)
        menuIcon?.isTemplate=false
        statusItem.button?.image=menuIcon
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "蓝色大肥鱼"
        statusItem.menu = makeMenu()
        act(.waving)
        update()
        panel.orderFrontRegardless()
        timer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer!, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func act(_ motion: PetMotion) {
        if model.motion.isPeeking { revealFromEdge() }
        let now = ProcessInfo.processInfo.systemUptime
        model.perform(motion, now: now)
        if motion == .headpat { lastHeadpat = now }
        updateSprite(now: now, localMouse: .zero, pointerNear: false)
    }

    func prepareForPress(revealPeek: Bool = true) {
        if revealPeek && model.motion.isPeeking { revealFromEdge() }
        model.stopChase(now:ProcessInfo.processInfo.systemUptime)
    }

    func dragPeek(to origin: NSPoint) {
        guard model.motion.isPeeking else { return }
        panel.setFrameOrigin(origin)
        let target=peekTarget()
        panel.setFrameOrigin(target)
        dockOrigin=target
        dockStart=ProcessInfo.processInfo.systemUptime-0.32
    }

    private func localMouse() -> NSPoint {
        view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    private func update() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.10, max(0, now-lastTick))
        lastTick = now
        let mouse = NSEvent.mouseLocation
        let local = localMouse()
        let source = view.sourcePoint(local)
        let pointerNear = hypot(local.x-view.bounds.midX, local.y-view.bounds.midY) < 240
        let hasPixel = view.sprite?.contains(source) ?? false
        panel.ignoresMouseEvents = !view.pressed && !hasPixel
        let mouseMoved = hypot(mouse.x-lastMouse.x, mouse.y-lastMouse.y) > 2
        lastMouse = mouse
        let buttonsDown = NSEvent.pressedMouseButtons != 0
        if model.motion.isPeeking {
            if !view.pressed && !menuOpen { updatePeek(now:now) }
            updateSprite(now:now,localMouse:local,pointerNear:false)
            return
        }
        respondToGaze(now:now,localMouse:local,pointerNear:pointerNear,buttonsDown:buttonsDown)
        respondToPointer(now:now,source:source,hasPixel:hasPixel,mouseMoved:mouseMoved,buttonsDown:buttonsDown)
        if buttonsDown && model.isChasing { model.stopChase(now:now) }
        if !view.pressed && !menuOpen && !buttonsDown {
            let area=(panel.screen ?? NSScreen.main)?.visibleFrame
            let head=NSPoint(x:panel.frame.minX+89*scale,y:panel.frame.minY+128*scale)
            let distance=hypot(mouse.x-head.x,mouse.y-head.y)
            let canChase=mouseMoved && !hasPixel && distance>125*scale && distance<480 && (area?.contains(mouse) ?? false)
            model.tick(now: now, pointerNear: pointerNear, canChase:canChase)
            if model.isChasing, let area=area {
                advanceChase(now:now,dt:dt,mouse:mouse,area:area)
            } else if model.motion.isWalking, let area=area {
                advanceWalk(dt:dt,area:area)
            }
        }
        updateSprite(now: now, localMouse: local, pointerNear: pointerNear)
    }

    private func respondToPointer(now: Double, source: NSPoint, hasPixel: Bool, mouseMoved: Bool, buttonsDown: Bool) {
        if model.motion.reactsToPointerMovement && hasPixel && view.isHead(source) && mouseMoved &&
            !view.pressed && !menuOpen && !buttonsDown && now-lastHeadpat > 2.2 &&
            (!model.isChasing || now>=model.chaseGraceUntil) {
            act(.headpat)
        }
    }

    private func respondToGaze(now: Double, localMouse: NSPoint, pointerNear: Bool, buttonsDown: Bool) {
        let source=view.sourcePoint(localMouse)
        model.observeGaze(dx:source.x-89,dyUp:80-source.y,now:now,
                          eligible:pointerNear && !view.pressed && !menuOpen && !buttonsDown)
    }

    private func advanceWalk(dt: Double, area: NSRect) {
        var origin=panel.frame.origin
        origin.x += (model.motion == .walkRight ? 1 : -1)*34*dt
        let hitLeft=origin.x<=area.minX, hitRight=origin.x>=area.maxX-panel.frame.width
        origin.x=PetModel.clampedX(origin.x,width:panel.frame.width,minimum:area.minX,maximum:area.maxX)
        panel.setFrameOrigin(origin)
        if hitLeft || hitRight { model.motion=hitLeft ? .walkRight : .walkLeft }
    }

    private func advanceChase(now: Double, dt: Double, mouse: NSPoint, area: NSRect) {
        guard area.contains(mouse) else { model.stopChase(now:now); return }
        let headX=panel.frame.minX+89*scale
        model.motion=mouse.x<headX ? .walkLeft : .walkRight
        let step=PetModel.chaseStep(origin:panel.frame.origin,size:panel.frame.size,
                                   headOffset:NSPoint(x:89*scale,y:128*scale),target:mouse,
                                   area:area,dt:dt,stopDistance:110*scale)
        panel.setFrameOrigin(step.origin)
        if step.arrived && now>=model.chaseGraceUntil { model.stopChase(now:now,pleased:true) }
        else if step.blocked { model.stopChase(now:now) }
    }

    private func updateSprite(now: Double, localMouse: NSPoint, pointerNear: Bool) {
        view.dizzyElapsed=model.motion == .dizzy ? max(0,now-model.started) : nil
        if model.motion == .affection {
            let sample=model.affectionSample(now:now)
            view.sprite=sprites.frames[sample.key]?[sample.index]
            return
        }
        if model.motion == .idle && pointerNear && !view.pressed {
            let p = view.sourcePoint(localMouse)
            if hypot(p.x-89, p.y-80) > 52, let looks = sprites.frames["look"] {
                let index = PetModel.lookIndex(dx: p.x-89, dyUp: 80-p.y)
                view.sprite = looks[index]
                return
            }
        }
        guard let frames = sprites.frames[model.motion.rawValue], !frames.isEmpty else { return }
        view.sprite = frames[model.frameIndex(now: now, count: frames.count)]
    }

    @objc private func screenChanged() {
        if model.motion.isPeeking { revealFromEdge() }
        keepOnScreen()
    }
    func keepOnScreen(allowPeeking: Bool = false) {
        let screens = NSScreen.screens
        let screen = screens.max { a, b in
            let x = a.visibleFrame.intersection(panel.frame), y = b.visibleFrame.intersection(panel.frame)
            return (x.isNull ? 0 : x.width*x.height) < (y.isNull ? 0 : y.width*y.height)
        } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        if allowPeeking && (panel.frame.minX<=area.minX+10 || panel.frame.maxX>=area.maxX-10) {
            let left=abs(panel.frame.minX-area.minX)<abs(panel.frame.maxX-area.maxX)
            if dockAfterDrag(left:left,now:ProcessInfo.processInfo.systemUptime,screen:screen) { return }
        }
        let x = PetModel.clampedX(panel.frame.minX, width: panel.frame.width, minimum: area.minX, maximum: area.maxX)
        let y = min(max(panel.frame.minY, area.minY), max(area.minY, area.maxY-panel.frame.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func savePosition() {
        let x:Double
        if model.motion.isPeeking, let area=dockArea {
            x=PetModel.clampedX(panel.frame.minX,width:panel.frame.width,minimum:area.minX,maximum:area.maxX)
        } else { x=panel.frame.minX }
        defaults.set(x, forKey: "petX")
        defaults.set(panel.frame.minY, forKey: "petY")
    }

    @discardableResult
    private func dockAfterDrag(left: Bool, now: Double, screen suppliedScreen: NSScreen?) -> Bool {
        guard let screen=suppliedScreen ?? panel.screen ?? NSScreen.main,
              model.beginPeek(left:left,now:now,userInitiated:true) else { return false }
        let area=screen.visibleFrame
        dockArea=NSRect(x:area.minX,y:screen.frame.minY,width:area.width,height:area.maxY-screen.frame.minY)
        dockVisibleArea=area
        panel.allowsTransparentOverflow=true
        dockStart=now
        dockOrigin=panel.frame.origin
        updateSprite(now:now,localMouse:.zero,pointerNear:false)
        return true
    }

    private func peekTarget() -> NSPoint {
        guard let area=dockArea else { return panel.frame.origin }
        let x=model.motion == .peekLeft ? area.minX-72*scale : area.maxX-120*scale
        let bounds=sprites.peekBounds[model.motion.rawValue] ?? NSRect(x:0,y:0,width:192,height:208)
        let y=PetModel.peekY(panel.frame.minY,content:bounds,scale:scale,area:area)
        return NSPoint(x:x,y:y)
    }

    private func updatePeek(now: Double) {
        let target=peekTarget()
        let t=min(1,max(0,(now-dockStart)/0.32))
        let eased=t*t*(3-2*t)
        panel.setFrameOrigin(NSPoint(x:dockOrigin.x+(target.x-dockOrigin.x)*eased,
                                     y:dockOrigin.y+(target.y-dockOrigin.y)*eased))
    }

    func revealFromEdge() {
        guard model.motion.isPeeking else { return }
        let left=model.motion == .peekLeft
        let area=dockVisibleArea ?? (panel.screen ?? NSScreen.main)?.visibleFrame
        model.reveal(now:ProcessInfo.processInfo.systemUptime)
        panel.allowsTransparentOverflow=false
        if let area=area {
            panel.setFrameOrigin(NSPoint(x:left ? area.minX+12 : area.maxX-panel.frame.width-12,
                                         y:PetModel.clampedX(panel.frame.minY,width:panel.frame.height,minimum:area.minY,maximum:area.maxY)))
        }
        dockArea=nil
        dockVisibleArea=nil
        updateSprite(now:ProcessInfo.processInfo.systemUptime,localMouse:.zero,pointerNear:false)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen=true
        model.stopChase(now:ProcessInfo.processInfo.systemUptime)
    }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen=false
        model.nextRandomDecision=max(model.nextRandomDecision,ProcessInfo.processInfo.systemUptime+5)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate=self
        let name = NSMenuItem(title: "蓝色大肥鱼", action: nil, keyEquivalent: "")
        name.isEnabled = false
        menu.addItem(name)
        menu.addItem(.separator())
        func add(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
            return item
        }
        _ = add("🍚 喂一碗大米饭", #selector(feed))
        _ = add("举碗要饭", #selector(waitForFood))
        _ = add("摸摸头", #selector(pat))
        _ = add("撒个娇（打滚）", #selector(askForAffection))
        _ = add("追着鼠标玩", #selector(playChase))
        _ = add("打个招呼", #selector(wave))
        _ = add("跳一下", #selector(jump))
        _ = add("去散步", #selector(walk))
        _ = add("睡觉", #selector(sleepPet))
        _ = add("叫醒", #selector(wake))
        menu.addItem(.separator())
        add("自动散步", #selector(toggleWalk)).state = model.automaticWalking ? .on : .off
        add("偶尔撒娇（4%）", #selector(toggleAffection)).state = model.occasionalAffection ? .on : .off
        add("偶尔追逐鼠标（4%）", #selector(toggleChasing)).state = model.mouseChasing ? .on : .off
        add("贴边躲藏探头", #selector(togglePeeking)).state = model.edgePeeking ? .on : .off
        add("显示在其他窗口上方", #selector(togglePinned)).state = pinned ? .on : .off
        let sizeMenu = NSMenu()
        for (label, value) in [("小",1.0),("中",1.25),("大",1.6)] {
            let item = NSMenuItem(title: label, action: #selector(changeSize(_:)), keyEquivalent: "")
            item.representedObject = value
            item.target = self
            item.state = abs(value-scale) < 0.01 ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        let help = NSMenuItem(title: "摸头 · 点碗喂饭 · 拖动移动 · 点击唤醒", action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)
        _ = add("退出蓝色大肥鱼", #selector(quit), key: "q")
        return menu
    }

    private func refreshMenu() { statusItem.menu = makeMenu() }
    @objc private func feed() { act(.eating) }
    @objc private func waitForFood() { act(.waiting) }
    @objc private func pat() { act(.headpat) }
    @objc private func askForAffection() { act(.affection) }
    @objc private func playChase() {
        if model.motion.isPeeking { revealFromEdge() }
        model.beginChase(now:ProcessInfo.processInfo.systemUptime,userInitiated:true)
    }
    @objc private func wave() { act(.waving) }
    @objc private func jump() { act(.jumping) }
    @objc private func walk() { act(.walkRight) }
    @objc private func sleepPet() { act(.sleeping) }
    @objc private func wake() { act(.idle) }
    @objc private func toggleWalk() {
        model.automaticWalking.toggle()
        defaults.set(model.automaticWalking, forKey: "automaticWalking")
        if !model.automaticWalking && model.motion.isWalking && !model.isChasing { act(.idle) }
        refreshMenu()
    }
    @objc private func togglePinned() {
        pinned.toggle()
        panel.level = pinned ? .floating : .normal
        refreshMenu()
    }
    @objc private func toggleAffection() {
        model.occasionalAffection.toggle()
        defaults.set(model.occasionalAffection,forKey:"occasionalAffection")
        if !model.occasionalAffection && model.motion == .affection { act(.idle) }
        refreshMenu()
    }
    @objc private func toggleChasing() {
        model.mouseChasing.toggle()
        defaults.set(model.mouseChasing,forKey:"mouseChasing")
        if !model.mouseChasing { model.stopChase(now:ProcessInfo.processInfo.systemUptime) }
        refreshMenu()
    }
    @objc private func togglePeeking() {
        model.edgePeeking.toggle()
        defaults.set(model.edgePeeking,forKey:"edgePeeking")
        if !model.edgePeeking { revealFromEdge() }
        refreshMenu()
    }
    @objc private func changeSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        scale = value
        panel.setContentSize(NSSize(width: 192*scale, height: 208*scale))
        defaults.set(value, forKey: "petScale")
        if model.motion.isPeeking { panel.setFrameOrigin(peekTarget()) }
        else { keepOnScreen() }
        refreshMenu()
    }
    @objc private func quit() {
        savePosition()
        NSApplication.shared.terminate(nil)
    }

    func writeViewPreview(to url: URL) throws {
        try writePreview(of:view,to:url)
    }
    private func writePreview(of target: NSView, to url: URL) throws {
        target.displayIfNeeded()
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else {
            throw NSError(domain: "BlueWhalePet", code: 4)
        }
        target.cacheDisplay(in: target.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "BlueWhalePet", code: 5)
        }
        try data.write(to: url)
    }

    func runBehaviorSmokeTest(at directory: URL) throws {
        timer?.invalidate()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let area=NSScreen.main?.visibleFrame else { throw NSError(domain:"BlueWhalePet",code:8) }
        var checks:[String]=[]
        func check(_ success: Bool, _ label: String) throws {
            if !success { throw NSError(domain:"BlueWhalePet",code:9,userInfo:[NSLocalizedDescriptionKey:label]) }
            checks.append(label)
        }
        func activate(_ title: String) throws {
            let item=makeMenu().items.first { $0.title == title }
            try check(item?.action != nil && NSApp.sendAction(item!.action!,to:item!.target,from:item),"Menu action: "+title)
        }
        func click(source: NSPoint) {
            let point=view.convert(NSPoint(x:source.x*scale,y:source.y*scale),to:nil)
            let time=ProcessInfo.processInfo.systemUptime
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:time,
                                        windowNumber:panel.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:time+0.1,
                                      windowNumber:panel.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            view.mouseDown(with:down)
            view.mouseUp(with:up)
        }
        panel.setFrameOrigin(NSPoint(x:area.minX+40,y:area.minY+40))
        for name in ["idle","running-right","running-left","waving","jumping","look","eating","sleeping","headpat","rolling","peek-left","peek-right"] {
            view.sprite=sprites.frames[name]![0]
            try writeViewPreview(to:directory.appendingPathComponent("size-"+name+".png"))
        }
        for index in 0..<16 {
            view.sprite=sprites.frames["look"]![index]
            try writeViewPreview(to:directory.appendingPathComponent(String(format:"gaze-%02d.png",index)))
        }
        try check(sprites.frames["look"]!.allSatisfy { $0.bitmap.pixelsHigh > 300 },
                  "Every gaze direction renders from original resolution")
        try check(statusItem.button?.image != nil && statusItem.button?.title == "", "Menu bar uses the DeepSeek whale image")
        if let button=statusItem.button { try writePreview(of:button,to:directory.appendingPathComponent("menu-bar-icon.png")) }
        for (title,motion,count) in [("摸摸头",PetMotion.headpat,6),("打个招呼",PetMotion.waving,4)] {
            try activate(title)
            let began=model.started
            for index in 0..<count {
                updateSprite(now:began+Double(index)*motion.frameSeconds+0.001,localMouse:.zero,pointerNear:false)
                try check(view.sprite?.image === sprites.frames[motion.rawValue]![index].image,
                          "\(motion) renders frame \(index) once in order")
            }
            respondToPointer(now:began+0.2,source:NSPoint(x:89,y:80),hasPixel:true,mouseMoved:true,buttonsDown:false)
            try check(model.started==began,"Hover cannot restart the \(motion) animation")
            model.tick(now:began+motion.duration!+0.001,pointerNear:true,randomRoll:{0.99})
            try check(model.motion == .idle,"\(motion) completes after one native animation cycle")
        }
        let gazeScale=scale
        for size in [1.0,1.25,1.6] {
            scale=size
            panel.setContentSize(NSSize(width:192*size,height:208*size))
            model=PetModel(now:0)
            for sample in 0...320 {
                let angle=Double(sample)/64*2*Double.pi
                respondToGaze(now:Double(sample)/64,
                              localMouse:NSPoint(x:(89+100*cos(angle))*size,y:(80-100*sin(angle))*size),
                              pointerNear:true,buttonsDown:false)
            }
            try check(model.motion == .idle,"Five gaze turns alone do not trigger dizziness at size \(size)")
            let angle=321.0/64*2*Double.pi
            respondToGaze(now:321.0/64,localMouse:NSPoint(x:(89+100*cos(angle))*size,y:(80-100*sin(angle))*size),
                          pointerNear:true,buttonsDown:false)
            try check(model.motion == .dizzy,"More than five gaze turns trigger seated dizziness at size \(size)")
            for (index,time) in [0.2,0.55,0.9,1.25].enumerated() {
                updateSprite(now:model.started+time,localMouse:.zero,pointerNear:true)
                try writeViewPreview(to:directory.appendingPathComponent("dizzy-\(size)-\(index).png"))
            }
            try check(view.sprite?.image === sprites.frames["dizzy"]![0].image && view.dizzyElapsed != nil,
                      "Dizzy state uses the high-resolution seated sprite and animated overlay")
            try check(view.isHead(NSPoint(x:89,y:136)) && !view.isBowl(NSPoint(x:89,y:136)),
                      "Seated dizzy head keeps a distinct click target at size \(size)")
            try check(view.isBowl(NSPoint(x:89,y:169)) && !view.isHead(NSPoint(x:89,y:169)),
                      "Seated dizzy bowl keeps a distinct click target at size \(size)")
            let first=try Data(contentsOf:directory.appendingPathComponent("dizzy-\(size)-0.png"))
            let second=try Data(contentsOf:directory.appendingPathComponent("dizzy-\(size)-1.png"))
            try check(first != second,"Dizzy sway and orbit visibly advance at size \(size)")
            model.tick(now:model.started+5.01,pointerNear:true,randomRoll:{0.99})
            updateSprite(now:model.started,localMouse:.zero,pointerNear:false)
            try check(model.motion == .idle && view.dizzyElapsed == nil,"Recovery removes the orbit overlay at size \(size)")
        }
        scale=gazeScale
        panel.setContentSize(NSSize(width:192*scale,height:208*scale))
        for (point,expected) in [(NSPoint(x:89,y:136),PetMotion.headpat),(NSPoint(x:89,y:169),.eating)] {
            act(.dizzy)
            click(source:point)
            try check(model.motion==expected && view.dizzyElapsed == nil,"Clicking seated dizzy pet starts \(expected) and clears the stars")
        }
        for blocked in ["drag","menu","buttons","far"] {
            model=PetModel(now:0)
            view.pressed=blocked == "drag"
            menuOpen=blocked == "menu"
            for sample in 0...400 {
                let angle=Double(sample)/64*2*Double.pi
                respondToGaze(now:Double(sample)/64,
                              localMouse:NSPoint(x:(89+100*cos(angle))*scale,y:(80-100*sin(angle))*scale),
                              pointerNear:blocked != "far",buttonsDown:blocked == "buttons")
            }
            try check(model.motion == .idle,"\(blocked) blocks the gaze orbit gesture")
            view.pressed=false
            menuOpen=false
        }
        act(.idle)
        try activate("举碗要饭")
        try check(model.motion == .waiting,"Bowl waiting animation is reachable from the menu")
        for index in 0..<6 {
            updateSprite(now:model.started+Double(index)*0.4+0.01,localMouse:.zero,pointerNear:true)
            try check(view.sprite?.image === sprites.frames["waiting"]![index].image,"Waiting renders its original frame \(index)")
            try writeViewPreview(to:directory.appendingPathComponent(String(format:"waiting-%02d.png",index)))
        }
        let visibleWindowCount=NSApp.windows.filter { $0.isVisible }.count
        try activate("撒个娇（打滚）")
        try check(model.motion == .affection && NSApp.windows.filter { $0.isVisible }.count == visibleWindowCount,
                  "Affection rolls without opening a speech bubble")
        for (index,time) in [0.0,0.31,0.49,0.67,0.85,1.03,1.21,1.43].enumerated() {
            updateSprite(now:model.started+time,localMouse:.zero,pointerNear:false)
            try writeViewPreview(to:directory.appendingPathComponent(String(format:"roll-%02d.png",index)))
        }
        try activate("追着鼠标玩")
        try check(model.isChasing,"Manual chase starts")
        let start=panel.frame.origin
        let target=NSPoint(x:min(area.maxX-20,start.x+89*scale+300),y:start.y+128*scale)
        for step in 0..<12 where model.isChasing {
            advanceChase(now:model.chaseStarted+Double(step)*0.1,dt:0.1,mouse:target,area:area)
        }
        try check(panel.frame.minX>start.x+10 && area.contains(panel.frame),"Controller moves toward mouse without leaving screen")
        prepareForPress()
        try check(!model.isChasing,"Mouse press interrupts chasing")
        try activate("睡觉")
        try check(model.motion == .sleeping,"Sleep menu remains available")
        let sleepTime=model.started
        respondToPointer(now:sleepTime+10,source:NSPoint(x:88,y:83),hasPixel:true,mouseMoved:true,buttonsDown:false)
        model.tick(now:sleepTime+1000,pointerNear:true,canChase:true,randomRoll:{0.01})
        try check(model.motion == .sleeping,"Moving over the sleeping head never wakes the pet")
        click(source:NSPoint(x:96,y:104))
        try check(model.motion == .idle,"A real view click wakes the sleeping pet")
        try activate("🍚 喂一碗大米饭")
        try check(model.motion == .eating && !model.isChasing,"Feeding takes precedence")
        for left in [true,false] {
            act(left ? .walkLeft : .walkRight)
            panel.setFrameOrigin(NSPoint(x:left ? area.minX+1 : area.maxX-panel.frame.width-1,y:area.minY+40))
            advanceWalk(dt:0.1,area:area)
            try check(model.motion == (left ? .walkRight : .walkLeft) && area.contains(panel.frame),
                      "Walking turns around at the \(left ? "left" : "right") edge without hiding")
            model.beginChase(now:ProcessInfo.processInfo.systemUptime)
            panel.setFrameOrigin(NSPoint(x:left ? area.minX : area.maxX-panel.frame.width,y:area.minY+40))
            advanceChase(now:model.chaseStarted+0.1,dt:0.1,
                         mouse:NSPoint(x:left ? area.minX+1 : area.maxX-1,y:area.maxY-1),area:area)
            try check(!model.isChasing && !model.motion.isPeeking && area.contains(panel.frame),
                      "Chasing stops at the \(left ? "left" : "right") edge without hiding")
        }

        func peekSnapshot(_ name: String) throws {
            try writeViewPreview(to:directory.appendingPathComponent(name+"-full.png"))
            let visible=panel.frame.intersection(dockArea ?? area)
            let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:rep)
            let ratio=Double(rep.pixelsWide)/view.bounds.width
            let rect=CGRect(x:(visible.minX-panel.frame.minX)*ratio,
                            y:(panel.frame.maxY-visible.maxY)*ratio,
                            width:visible.width*ratio,height:visible.height*ratio)
            guard let image=rep.cgImage?.cropping(to:rect),
                  let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {
                throw NSError(domain:"BlueWhalePet",code:10)
            }
            try data.write(to:directory.appendingPathComponent(name+"-visible.png"))
        }

        act(.idle)
        panel.setFrameOrigin(NSPoint(x:area.minX+3,y:area.minY+40))
        keepOnScreen(allowPeeking:true)
        let leftStart=dockStart
        updatePeek(now:leftStart+0.4)
        updateSprite(now:leftStart+0.4,localMouse:.zero,pointerNear:false)
        try check(model.motion == .peekLeft && panel.frame.minX<area.minX && panel.frame.maxX>area.minX,"Dragging to left edge hides body and leaves visible peek")
        try peekSnapshot("peek-left")
        updatePeek(now:leftStart+1)
        updatePeek(now:leftStart+10)
        try check(model.motion == .peekLeft,"Time and pointer proximity cannot reveal the peeking pet")
        prepareForPress()
        try check(model.motion == .idle && area.contains(panel.frame),"Clicking the left peek reveals the pet")

        panel.setFrameOrigin(NSPoint(x:area.maxX-panel.frame.width-3,y:area.minY+40))
        keepOnScreen(allowPeeking:true)
        let rightStart=dockStart
        updatePeek(now:rightStart+0.4)
        updateSprite(now:rightStart+0.4,localMouse:.zero,pointerNear:false)
        try check(model.motion == .peekRight && panel.frame.maxX>area.maxX && panel.frame.minX<area.maxX,"Right edge peek is visible")
        try peekSnapshot("peek-right")
        prepareForPress()
        try check(model.motion == .idle && area.contains(panel.frame),"Clicking peek reveals full pet")
        let originalScale=scale
        let screen=NSScreen.main!
        let pixelTolerance=1.01
        for size in [1.0,1.25,1.6] {
            scale=size
            panel.setContentSize(NSSize(width:192*scale,height:208*scale))
            for left in [true,false] {
                act(.idle)
                panel.setFrameOrigin(NSPoint(x:left ? area.minX+3 : area.maxX-panel.frame.width-3,y:area.minY+40))
                keepOnScreen(allowPeeking:true)
                updatePeek(now:dockStart+0.4)
                let original=panel.frame.origin
                prepareForPress(revealPeek:false)
                try check(model.motion.isPeeking && panel.frame.origin == original,"Pressing a peeking head does not jump before dragging")
                dragPeek(to:NSPoint(x:original.x,y:screen.frame.minY-1000))
                updatePeek(now:ProcessInfo.processInfo.systemUptime+0.5)
                let content=sprites.peekBounds[model.motion.rawValue]!
                let headBottom=panel.frame.minY+(208-content.maxY)*scale
                try check(headBottom>=screen.frame.minY && headBottom-screen.frame.minY<=pixelTolerance,"Peek reaches the bottom \(left ? "left" : "right") corner at size \(size) (offset \(headBottom-screen.frame.minY) pt)")
                if size==1.25 { try peekSnapshot(left ? "bottom-left" : "bottom-right") }
                dragPeek(to:NSPoint(x:original.x,y:area.maxY+1000))
                let headTop=panel.frame.minY+(208-content.minY)*scale
                try check(headTop<=area.maxY && area.maxY-headTop<=pixelTolerance,"Peek stays below the menu bar at size \(size) (offset \(headTop-area.maxY) pt)")
                prepareForPress()
                try check(model.motion == .idle && area.contains(panel.frame),"Clicking a corner peek restores the full pet on screen")
            }
        }
        scale=originalScale
        panel.setContentSize(NSSize(width:192*scale,height:208*scale))
        keepOnScreen()
        try activate("偶尔撒娇（4%）")
        try activate("偶尔追逐鼠标（4%）")
        try activate("贴边躲藏探头")
        try check(!model.occasionalAffection && !model.mouseChasing && !model.edgePeeking,"All three behavior switches work independently")
        let report:[String:Any]=["ok":true,"version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown","checks":checks,
                                 "previewSource":"Actual AppKit view rendering and screen-intersection cropping; no desktop screenshot", 
                                 "screenFrame":[area.minX,area.minY,area.width,area.height]]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:directory.appendingPathComponent("ui-smoke-test.json"))
        print(String(data:data,encoding:.utf8)!)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: PetController?
    let testing=CommandLine.arguments.contains("--render-preview") || CommandLine.arguments.contains("--behavior-smoke-test")
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let resources = Bundle.main.resourceURL else { throw NSError(domain: "BlueWhalePet", code: 6) }
            controller = try PetController(resources: resources,testing:testing)
            if let index=CommandLine.arguments.firstIndex(of:"--behavior-smoke-test"),CommandLine.arguments.count>index+1 {
                try controller?.runBehaviorSmokeTest(at:URL(fileURLWithPath:CommandLine.arguments[index+1]))
                DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { NSApp.terminate(nil) }
                return
            }
            if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
               CommandLine.arguments.count > index+1 {
                let url = URL(fileURLWithPath: CommandLine.arguments[index+1])
                controller?.act(.eating)
                try controller?.writeViewPreview(to: url)
                print("Rendered real AppKit view to \(url.path)")
                DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { NSApp.terminate(nil) }
            }
        } catch {
            if testing { fputs("Behavior test failed: \(error)\n",stderr); exit(1) }
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        if !testing { controller?.savePosition() }
    }
}
