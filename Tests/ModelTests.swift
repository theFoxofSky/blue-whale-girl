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
    return passed
}
