import Foundation
import CoreGraphics

func runModelTests() -> [String] {
    var passed: [String] = []
    func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label)
        passed.append(label)
    }
    var pet = PetModel(now: 0)
    pet.tick(now: 23, pointerNear: true)
    check(pet.motion == .idle, "Mouse proximity prevents surprise walking")
    pet.tick(now: 24, pointerNear: false)
    check(pet.motion == .walkRight, "Automatic walking starts")
    pet.tick(now: 33, pointerNear: false, randomRoll:{0.99})
    check(pet.motion == .idle, "Walking returns to idle")
    pet.perform(.eating, now: 34)
    pet.tick(now: 36, pointerNear: false)
    check(pet.motion == .eating, "Meal plays without auto-walk interruption")
    pet.tick(now: 38, pointerNear: false)
    check(pet.motion == .idle, "Meal completes")
    pet.tick(now: 155, pointerNear: false)
    check(pet.motion == .sleeping, "Two minutes without interaction causes sleep")
    pet.tick(now: 400, pointerNear: false)
    check(pet.motion == .sleeping, "Sleep persists")
    pet.perform(.headpat, now: 401)
    check(pet.motion == .headpat && pet.lastInteraction == 401, "Headpat wakes and resets inactivity")
    pet.perform(.eating, now: 402)
    check(pet.motion == .eating, "Explicit feeding takes precedence over a reaction")
    check(PetModel.lookIndex(dx: 0, dyUp: 1) == 0, "Up gaze mapping")
    check(PetModel.lookIndex(dx: 1, dyUp: 0) == 4, "Right gaze mapping")
    check(PetModel.lookIndex(dx: 0, dyUp: -1) == 8, "Down gaze mapping")
    check(PetModel.lookIndex(dx: -1, dyUp: 0) == 12, "Left gaze mapping")
    check(PetModel.clampedX(980, width: 240, minimum: 0, maximum: 1000) == 760, "Right screen edge clamp")
    check(PetModel.clampedX(-20, width: 240, minimum: 0, maximum: 1000) == 0, "Left screen edge clamp")
    var blinking=PetModel(now:0)
    blinking.automaticWalking=false
    var openBeforeBlink=true
    for frame in 0..<240 {
        let time=Double(frame)/30
        blinking.tick(now:time,pointerNear:true,randomRoll:{0.99})
        let index=blinking.frameIndex(now:time,count:6)
        openBeforeBlink = openBeforeBlink && (index==0 || index==5)
    }
    check(openBeforeBlink,"Idle eyes remain open before the first blink")
    blinking.tick(now:8,pointerNear:true)
    check(blinking.frameIndex(now:8.09,count:6)==3,"Blink briefly closes the eyes")
    check([0,5].contains(blinking.frameIndex(now:8.2,count:6)),"Blink ends within 160 milliseconds")
    check(blinking.nextBlink>=14 && blinking.nextBlink<=18,"Next blink waits six to ten seconds")
    var affectionCount=0, chaseCount=0
    for index in 0..<10000 {
        switch PetModel.randomBehavior(roll:(Double(index)+0.5)/10000) {
        case .affection: affectionCount+=1
        case .chase: chaseCount+=1
        case .none: break
        }
    }
    check(affectionCount==400 && chaseCount==400, "Each random behavior has exactly 4 percent of the sample space")
    check(affectionCount+chaseCount<1000, "Combined automatic behavior probability stays below 10 percent")
    check(PetModel.randomBehavior(roll:0.04) == .chase && PetModel.randomBehavior(roll:0.08) == .none, "Probability boundaries do not overlap")
    var rare=PetModel(now:0)
    rare.automaticWalking=false
    var draws=0
    for frame in 1...1800 {
        rare.tick(now:Double(frame)/30,pointerNear:true,randomRoll:{ draws+=1; return 0.99 })
    }
    check(draws==2, "Only two random draws over sixty seconds at thirty frames per second")
    rare.tick(now:90,pointerNear:true,canChase:true,randomRoll:{0.02})
    check(rare.motion == .affection && !rare.isChasing, "Affection event is exclusive")
    check(rare.affectionSample(now:90.8).key == "rolling", "Affection uses the body-roll animation")
    var rolling=PetModel(now:0)
    rolling.perform(.affection,now:1)
    rolling.tick(now:3.3,pointerNear:true)
    check(rolling.motion == .idle,"One roll returns to idle automatically")
    rare.perform(.eating,now:91)
    rare.nextRandomDecision=92
    rare.tick(now:92,pointerNear:true,canChase:true,randomRoll:{0.05})
    check(rare.motion == .eating && !rare.isChasing, "Meal is protected from random chase")
    rare.perform(.idle,now:95)
    rare.tick(now:125,pointerNear:true,canChase:true,randomRoll:{0.05})
    check(rare.isChasing, "Eligible mouse movement can trigger rare chase")
    rare.tick(now:131.1,pointerNear:true,canChase:true,randomRoll:{0.99})
    check(!rare.isChasing, "Chase is bounded to six seconds")
    rare.mouseChasing=false
    rare.nextRandomDecision=160
    rare.tick(now:160,pointerNear:true,canChase:true,randomRoll:{0.05})
    check(!rare.isChasing, "Mouse chase toggle disables automatic chase")
    rare.occasionalAffection=false
    rare.nextRandomDecision=190
    rare.tick(now:190,pointerNear:true,randomRoll:{0.02})
    check(rare.motion != .affection, "Affection toggle disables automatic affection")
    check(!rare.beginPeek(left:true,now:191,userInitiated:false), "Automatic movement cannot enter peek state")
    check(rare.beginPeek(left:true,now:191,userInitiated:true), "Dragging to the left edge can enter peek state")
    rare.tick(now:200,pointerNear:false,canChase:true,randomRoll:{0.05})
    check(rare.motion == .peekLeft && !rare.isChasing, "Peeking is protected from random events")
    rare.tick(now:200.5,pointerNear:true,canChase:true,randomRoll:{0.02})
    check(rare.motion == .peekLeft,"Pointer proximity does not reveal a peeking pet")
    rare.reveal(now:201)
    check(rare.motion == .idle && !rare.beginPeek(left:false,now:202,userInitiated:false), "Revealed pet cannot automatically hide again")
    check(rare.beginPeek(left:false,now:210,userInitiated:true), "Dragging to the right edge can hide again")
    rare.edgePeeking=false
    rare.reveal(now:211)
    check(!rare.beginPeek(left:true,now:230,userInitiated:true), "Peeking toggle is respected")
    let step=PetModel.chaseStep(origin:.zero,size:CGSize(width:200,height:200),headOffset:.zero,
                               target:CGPoint(x:111,y:0),area:CGRect(x:0,y:0,width:1000,height:800),dt:0.1,stopDistance:110)
    check(abs(step.origin.x-1)<0.001 && step.arrived, "Chase stops at its comfort distance without overshooting")
    let bound=PetModel.chaseStep(origin:CGPoint(x:800,y:600),size:CGSize(width:200,height:200),headOffset:.zero,
                                target:CGPoint(x:1100,y:900),area:CGRect(x:0,y:0,width:1000,height:800),dt:0.1,stopDistance:110)
    check(bound.origin == CGPoint(x:800,y:600) && bound.blocked, "Chase stays inside screen on both axes")
    rare.beginChase(now:300,userInitiated:true)
    check(rare.chaseGraceUntil==301, "Manual chase gives time to move the cursor away from the menu")
    check(!PetMotion.sleeping.reactsToPointerMovement,"Sleeping ignores pointer movement")
    check(!PetMotion.waiting.reactsToPointerMovement,"Pointer movement does not interrupt the bowl animation")
    var waiting=PetModel(now:0)
    waiting.automaticWalking=false
    waiting.tick(now:44,pointerNear:true,randomRoll:{0.99})
    check(waiting.motion == .idle,"Bowl animation is not triggered continuously")
    waiting.tick(now:45,pointerNear:true,randomRoll:{0.99})
    check(waiting.motion == .waiting,"Idle pet occasionally raises its bowl")
    check(waiting.nextWaiting>=90 && waiting.nextWaiting<=120,"Bowl animation has a 45 to 75 second cooldown")
    check(waiting.lastInteraction==0,"Automatic bowl animation does not reset the sleep timer")
    check(waiting.frameIndex(now:47.39,count:6)==5,"Bowl animation reaches the final lowered-bowl frame")
    waiting.tick(now:47.41,pointerNear:true,randomRoll:{0.99})
    check(waiting.motion == .idle,"Bowl animation plays once and returns to idle")
    waiting.tick(now:120,pointerNear:true,randomRoll:{0.99})
    check(waiting.motion == .sleeping,"Automatic bowl animation still allows inactivity sleep")
    waiting.tick(now:1000,pointerNear:true,canChase:true,randomRoll:{0.01})
    check(waiting.motion == .sleeping,"Pointer proximity and expired animation timers cannot wake the pet")

    for (motion,count) in [(PetMotion.headpat,6)] {
        var once=PetModel(now:0)
        once.automaticWalking=false
        once.perform(motion,now:1)
        let indices=(0..<count).map { once.frameIndex(now:1+Double($0)*motion.frameSeconds+0.001,count:count) }
        check(indices==Array(0..<count),"\(motion) plays every frame exactly once")
        check(once.frameIndex(now:1+motion.duration!+0.1,count:count)==count-1,
              "\(motion) cannot wrap to its first frame before the next tick")
        once.tick(now:1+motion.duration!-0.001,pointerNear:true,randomRoll:{0.99})
        check(once.motion==motion,"\(motion) keeps its final frame until completion")
        once.tick(now:1+motion.duration!+0.001,pointerNear:true,randomRoll:{0.99})
        check(once.motion == .idle,"\(motion) returns to idle after one cycle")
        check(!motion.reactsToPointerMovement,"Pointer movement cannot restart \(motion) mid-cycle")
    }
    var greeting=PetModel(now:0)
    greeting.perform(.waving,now:1)
    let greetingSamples=(0..<PetModel.greetingFrames.count).map {
        greeting.greetingSample(now:1+Double($0)*PetMotion.waving.frameSeconds+0.001)
    }
    check(greetingSamples.count==12,"Greeting contains twelve pose steps")
    check(Set(greetingSamples.map { "\($0.key):\($0.index)" }).count==8,"Greeting uses eight distinct original and new poses")
    check(greetingSamples.first!.key=="waving" && greetingSamples.first!.index==0 &&
          greetingSamples.last!.key=="waving" && greetingSamples.last!.index==3,"Greeting raises and lowers the hand once")
    check(PetMotion.waving.duration!>=1.5 && PetMotion.waving.duration!<=2.0,"Greeting gives time for several natural hand swings")
    greeting.tick(now:1+PetMotion.waving.duration!+0.001,pointerNear:true,randomRoll:{0.99})
    check(greeting.motion == .idle,"Greeting finishes one complete hand-waving sequence")

    func orbit(_ pet: inout PetModel, start: Double, turns: Double,
               direction: Double = 1, fromTurns: Double = 0, eligible: Bool = true) -> Bool {
        for sample in 0...Int((turns*64).rounded()) {
            let angle=(fromTurns+direction*Double(sample)/64)*2*Double.pi
            if pet.observeGaze(dx:100*cos(angle),dyUp:100*sin(angle),now:start+Double(sample)/64,eligible:eligible) {
                return true
            }
        }
        return false
    }
    for direction in [1.0,-1.0] {
        var dizzy=PetModel(now:0)
        check(!orbit(&dizzy,start:0,turns:5,direction:direction),
              "Exactly five turns do not trigger dizziness (direction \(direction))")
        check(orbit(&dizzy,start:5,turns:0.125,direction:direction,fromTurns:5*direction),
              "More than five continuous turns trigger dizziness (direction \(direction))")
        check(dizzy.motion == .dizzy && !dizzy.isChasing,"Orbit enters the seated dizzy state")
        let began=dizzy.started
        dizzy.tick(now:began+4.99,pointerNear:true,canChase:true,randomRoll:{0.01})
        check(dizzy.motion == .dizzy,"Dizziness is protected from automatic behaviors")
        dizzy.tick(now:began+5.01,pointerNear:true,randomRoll:{0.99})
        check(dizzy.motion == .idle,"Dizziness recovers after five seconds")
    }
    var wobble=PetModel(now:0)
    for sample in 0..<2000 {
        let angle=sample%2 == 0 ? 0.0 : Double.pi/3
        wobble.observeGaze(dx:100*cos(angle),dyUp:100*sin(angle),now:Double(sample)/64,eligible:true)
    }
    check(wobble.motion == .idle,"Repeated back-and-forth mouse movements do not add up to circles")
    var reversed=PetModel(now:0)
    check(!orbit(&reversed,start:0,turns:2.75),"Partial orbit is below the threshold")
    check(!orbit(&reversed,start:2.75,turns:2.75,direction:-1,fromTurns:2.75),
          "Reversing direction cancels angular progress instead of counting both paths")
    var interrupted=PetModel(now:0)
    _=orbit(&interrupted,start:0,turns:3)
    interrupted.observeGaze(dx:100,dyUp:0,now:3.1,eligible:false)
    check(!orbit(&interrupted,start:3.2,turns:3),"Leaving the gaze area or blocking input clears partial turns")
    var paused=PetModel(now:0)
    _=orbit(&paused,start:0,turns:3)
    paused.observeGaze(dx:100,dyUp:0,now:5,eligible:true)
    check(!orbit(&paused,start:5,turns:3),"A pause between circles starts a new gesture")
    var jumped=PetModel(now:0)
    for sample in 0..<100 {
        let angle=Double(sample)*Double.pi*0.75
        jumped.observeGaze(dx:100*cos(angle),dyUp:100*sin(angle),now:Double(sample)/30,eligible:true)
    }
    check(jumped.motion == .idle,"Large cursor jumps cannot fabricate completed circles")
    var tooClose=PetModel(now:0)
    for sample in 0..<400 {
        let angle=Double(sample)/64*2*Double.pi
        tooClose.observeGaze(dx:20*cos(angle),dyUp:20*sin(angle),now:Double(sample)/64,eligible:true)
    }
    check(tooClose.motion == .idle,"Small movements over the face do not count as orbiting the head")
    for motion in [PetMotion.sleeping,.waiting,.eating,.headpat,.waving,.affection,.peekLeft,.peekRight] {
        var protected=PetModel(now:0)
        protected.perform(motion,now:0)
        check(!orbit(&protected,start:0,turns:6) && protected.motion==motion,
              "Mouse circles cannot interrupt \(motion)")
    }
    for firstDirection in [1.0,-1.0] {
        var consecutive=PetModel(now:0)
        check(orbit(&consecutive,start:0,turns:5.125,direction:firstDirection),"First orbit works before changing direction")
        let recovered=consecutive.started+5.01
        consecutive.tick(now:recovered,pointerNear:true,randomRoll:{0.99})
        check(consecutive.motion == .idle,"Dizzy animation recovers before a new gesture")
        check(orbit(&consecutive,start:recovered+0.01,turns:5.125,direction:-firstDirection),
              "Opposite direction triggers immediately after recovery (first direction \(firstDirection))")
        consecutive.perform(.eating,now:consecutive.started+0.5)
        check(consecutive.motion == .eating,"An explicit click action can interrupt dizziness")
    }
    return passed
}
