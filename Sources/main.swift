import AppKit

if CommandLine.arguments.contains("--self-test") {
    do {
        var checks = runModelTests()
        let sprites = try SpriteStore(resources: Bundle.main.resourceURL!)
        let count = sprites.frames.values.reduce(0) { $0 + $1.count }
        precondition(count == 104, "Expected 103 original frames and one seated dizzy sprite")
        checks.append("All 104 animation frames load")
        for frames in sprites.frames.values {
            for frame in frames {
                let bounds=frame.opaqueBounds()
                precondition(bounds.minX>0 && bounds.minY>0 && bounds.maxX<192 && bounds.maxY<208,"Display calibration must not clip artwork")
            }
        }
        checks.append("All calibrated sprites retain transparent margins")
        precondition(sprites.frames.values.flatMap { $0 }.allSatisfy { $0.bitmap.pixelsHigh>208 },
                     "Original sprite pixels must not be replaced by a 192x208 intermediate bitmap")
        checks.append("All animations keep original-resolution backing pixels")
        let looks=sprites.frames["look"]!
        precondition(looks.count == 16 && looks.allSatisfy {
            guard let feet=$0.registrationFeet else { return false }
            return abs(feet.midX-87)<0.01 && abs(feet.maxY-202)<0.01 && abs(feet.width-33.5)<0.01
        },"Gaze directions must share body scale and ground anchor")
        checks.append("All sixteen gaze directions share scale and ground anchor")
        let idle = sprites.frames["idle"]![0]
        precondition(idle.contains(NSPoint(x: 88, y: 83)), "Head hit mask must be opaque")
        precondition(idle.contains(NSPoint(x: 88, y: 128)), "Bowl hit mask must be opaque")
        precondition(!idle.contains(NSPoint(x: 1, y: 1)), "Transparent corners pass mouse through")
        checks.append("Head, bowl and transparent hit masks")
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 240, height: 260))
        precondition(view.isHead(NSPoint(x: 88,y: 83)))
        precondition(view.isBowl(NSPoint(x: 88,y: 128)))
        precondition(!view.isHead(NSPoint(x: 88,y: 128)))
        checks.append("Head and bowl targets are distinct")
        let data = try JSONSerialization.data(withJSONObject: ["ok":true,"checks":checks,"frameCount":count], options:[.prettyPrinted,.sortedKeys])
        print(String(data:data,encoding:.utf8)!)
    } catch {
        fputs("Self-test failed: \(error)\n", stderr)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
