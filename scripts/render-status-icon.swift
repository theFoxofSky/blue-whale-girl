import AppKit
let source=URL(fileURLWithPath:CommandLine.arguments[1])
let destination=URL(fileURLWithPath:CommandLine.arguments[2])
guard let image=NSImage(contentsOf:source) else { fatalError("Cannot decode SVG") }
let view=NSImageView(frame:NSRect(x:0,y:0,width:60.3,height:45.4))
view.image=image
view.imageScaling = .scaleProportionallyUpOrDown
try view.dataWithPDF(inside:view.bounds).write(to:destination)
print("Saved vector menu icon: \(destination.path)")
