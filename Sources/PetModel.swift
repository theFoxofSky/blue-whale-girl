import Foundation
import CoreGraphics

enum PetMotion: String, CaseIterable {
    case idle, walkRight = "running-right", walkLeft = "running-left"
    case waving, jumping, waiting, eating, sleeping, headpat, affection
    case peekLeft = "peek-left", peekRight = "peek-right"
    var isWalking: Bool { self == .walkRight || self == .walkLeft }
    var isPeeking: Bool { self == .peekLeft || self == .peekRight }
    var reactsToPointerMovement: Bool {
        self == .idle || isWalking || self == .waving || self == .headpat
    }
    var duration: Double? {
        switch self {
        case .eating: return 3.6
        case .headpat: return 2.0
        case .waving: return 1.8
        case .jumping: return 0.9
        case .affection: return 2.2
        case .waiting: return 2.4
        case .walkRight, .walkLeft: return 8.0
        default: return nil
        }
    }
    var frameSeconds: Double {
        switch self {
        case .sleeping: return 0.42
        case .eating: return 0.20
        case .headpat: return 0.17
        case .walkRight, .walkLeft: return 0.14
        case .jumping: return 0.18
        case .waving: return 0.15
        case .waiting: return 0.4
        case .idle, .affection, .peekLeft, .peekRight: return 0.24
        }
    }
}

struct PetModel {
    var motion: PetMotion = .idle
    var started: Double
    var lastInteraction: Double
    var nextWalk: Double
    private(set) var nextWaiting: Double
    var automaticWalking = true
    var occasionalAffection = true
    var mouseChasing = true
    var edgePeeking = true
    private(set) var isChasing = false
    private(set) var chaseStarted: Double = 0
    private(set) var chaseGraceUntil: Double = 0
    private(set) var nextBlink: Double
    private(set) var blinkStarted = -Double.infinity
    var nextRandomDecision: Double
    var chaseAllowedAfter: Double = 0
    let sleepAfter: Double = 120
    static let decisionInterval: Double = 30
    static let affectionProbability: Double = 0.04
    static let chaseProbability: Double = 0.04

    init(now: Double) {
        started = now
        lastInteraction = now
        nextWalk = now + 22
        nextWaiting = now + 45
        nextRandomDecision = now + Self.decisionInterval
        nextBlink = now + 8
    }

    mutating func perform(_ next: PetMotion, now: Double, userInitiated: Bool = true) {
        if next == .idle && motion != .idle {
            nextBlink=now+Double.random(in:6...10)
            blinkStarted = -Double.infinity
        }
        motion = next
        started = now
        isChasing = false
        if next == .waiting { nextWaiting = now + Double.random(in:45...75) }
        if userInitiated {
            lastInteraction = now
            nextRandomDecision = now + Self.decisionInterval
            chaseAllowedAfter = now + 4
        }
        nextWalk = now + 24
    }

    mutating func beginChase(now: Double, userInitiated: Bool = false) {
        perform(.walkRight, now: now, userInitiated: userInitiated)
        isChasing = true
        chaseStarted = now
        chaseGraceUntil = userInitiated ? now+1 : now
    }

    mutating func stopChase(now: Double, pleased: Bool = false) {
        guard isChasing else { return }
        perform(pleased ? .headpat : .idle, now: now, userInitiated: false)
        chaseAllowedAfter = now + 15
    }

    @discardableResult
    mutating func beginPeek(left: Bool, now: Double, userInitiated: Bool) -> Bool {
        guard edgePeeking, userInitiated else { return false }
        perform(left ? .peekLeft : .peekRight, now: now)
        return true
    }

    mutating func reveal(now: Double) {
        guard motion.isPeeking else { return }
        perform(.idle, now: now)
    }

    enum RandomBehavior: Equatable { case none, affection, chase }
    static func randomBehavior(roll: Double) -> RandomBehavior {
        guard roll >= 0 && roll < 1 else { return .none }
        if roll < affectionProbability { return .affection }
        if roll < affectionProbability + chaseProbability { return .chase }
        return .none
    }

    mutating func tick(now: Double, pointerNear: Bool, canChase: Bool = false,
                       randomRoll: () -> Double = { Double.random(in: 0..<1) }) {
        if motion == .sleeping || motion.isPeeking { return }
        if isChasing && now - chaseStarted >= 6 { stopChase(now: now) }
        if let duration = motion.duration, now - started >= duration {
            perform(.idle, now: now, userInitiated: false)
        }
        if !isChasing && now - lastInteraction >= sleepAfter && (motion == .idle || motion.isWalking) {
            perform(.sleeping, now: now, userInitiated: false)
            return
        }
        // Exactly one shared draw per opportunity; the two events cannot stack.
        if now >= nextRandomDecision {
            nextRandomDecision = now + Self.decisionInterval
            if !isChasing && (motion == .idle || motion.isWalking) && now-lastInteraction > 3 {
                switch Self.randomBehavior(roll: randomRoll()) {
                case .affection where occasionalAffection:
                    perform(.affection, now: now, userInitiated: false)
                case .chase where mouseChasing && canChase && now >= chaseAllowedAfter:
                    beginChase(now: now)
                default: break
                }
            }
        }
        if motion == .idle && now >= nextWaiting && now-lastInteraction >= 8 {
            perform(.waiting, now:now, userInitiated:false)
        }
        if motion == .idle && automaticWalking && now >= nextWalk && !pointerNear {
            perform(.walkRight, now: now, userInitiated: false)
        }
        if motion == .idle && now>=nextBlink {
            blinkStarted=now
            nextBlink=now+Double.random(in:6...10)
        }
    }

    func frameIndex(now: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        if motion == .idle && count>=6 {
            let blink=now-blinkStarted
            if blink>=0 && blink<0.16 { return [1,2,3,4][min(3,Int(blink/0.04))] }
            return Int(max(0,now-started)/0.8)%2 == 0 ? 0 : 5
        }
        if motion.isPeeking { return (now-started).truncatingRemainder(dividingBy: 3.8) >= 3.62 ? min(1,count-1) : 0 }
        return Int(max(0, now - started) / motion.frameSeconds) % count
    }

    func affectionSample(now: Double) -> (key: String, index: Int) {
        let elapsed = max(0,now-started)
        let ends: [Double] = [0.30,0.48,0.66,0.84,1.02,1.20,1.42]
        return ("rolling", ends.firstIndex(where: { elapsed < $0 }) ?? 7)
    }

    struct ChaseStep {
        let origin: CGPoint
        let arrived: Bool
        let blocked: Bool
    }
    static func chaseStep(origin: CGPoint, size: CGSize, headOffset: CGPoint,
                          target: CGPoint, area: CGRect, dt: Double, stopDistance: Double) -> ChaseStep {
        let dx=target.x-origin.x-headOffset.x, dy=target.y-origin.y-headOffset.y
        let distance=hypot(dx,dy)
        guard distance.isFinite, distance>stopDistance else {
            return ChaseStep(origin:origin,arrived:true,blocked:false)
        }
        let step=min(100*max(0,min(dt,0.1)),distance-stopDistance)
        let wanted=CGPoint(x:origin.x+dx/distance*step,y:origin.y+dy/distance*step)
        let point=CGPoint(x:clampedX(wanted.x,width:size.width,minimum:area.minX,maximum:area.maxX),
                          y:clampedX(wanted.y,width:size.height,minimum:area.minY,maximum:area.maxY))
        return ChaseStep(origin:point,arrived:distance-step<=stopDistance+0.1,
                         blocked:hypot(point.x-wanted.x,point.y-wanted.y)>0.25)
    }

    static func lookIndex(dx: Double, dyUp: Double) -> Int {
        let angle = atan2(dx, dyUp)
        let positive = angle < 0 ? angle + 2 * Double.pi : angle
        return Int((positive / (2 * Double.pi) * 16).rounded()) % 16
    }

    static func clampedX(_ x: Double, width: Double, minimum: Double, maximum: Double) -> Double {
        min(max(x, minimum), max(minimum, maximum - width))
    }

    static func peekY(_ y: Double, content: CGRect, scale: Double, area: CGRect) -> Double {
        let bottom=(208-content.maxY)*scale
        let top=(208-content.minY)*scale
        // NSWindow snaps origins to logical points; round inward so no visible pixel is cut off.
        let lower=ceil(area.minY-bottom), upper=floor(area.maxY-top)
        return min(max(y,lower),max(lower,upper))
    }
}
