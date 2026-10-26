import AppKit
import CryptoKit
import ImageIO

@main
struct AssetChecks {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "AssetRegression", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() throws {
        let project = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = project.appendingPathComponent("HighResolution")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as! [String: Any]
        let frames = manifest["frames"] as! [String: [[String: Any]]]
        var checks: [String] = []
        var measurements: [[String: Any]] = []

        if CommandLine.arguments.count == 2 {
            let fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: project.appendingPathComponent("Tests/Fixtures/high-resolution-sha256.json")))
            let expected = ["idle":6,"running-right":8,"running-left":8,"waving":4,"jumping":5,
                            "failed":8,"waiting":6,"running":6,"review":6,"look":16,
                            "eating":6,"sleeping":6,"headpat":6,"rolling":8,"peek-left":2,"peek-right":2]
            try require(Set(frames.keys) == Set(expected.keys), "Animation states changed")
            var files: Set<String> = ["manifest.json"]
            for (name, count) in expected {
                try require(frames[name]!.count == count, "Unexpected frame count: \(name)")
                for record in frames[name]! {
                    let file = record["file"] as! String
                    try require(!file.hasPrefix("/") && !file.split(separator: "/").contains(".."), "Nonportable asset path")
                    let url = directory.appendingPathComponent(file)
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                        throw NSError(domain: "AssetRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot decode \(file)"])
                    }
                    let size = record["pixelSize"] as! [Int]
                    try require(size == [image.width, image.height] && image.height > 208, "Resolution changed: \(file)")
                    files.insert(file)
                }
            }
            try require(files.count == 104 && Set(fixture.keys) == files, "Unexpected image inventory")
            for file in files {
                let digest = SHA256.hash(data: try Data(contentsOf: directory.appendingPathComponent(file))).map { String(format: "%02x", $0) }.joined()
                try require(digest == fixture[file], "Original artwork bytes changed: \(file)")
            }
            checks = ["All 16 animation states and 103 frames are present",
                      "All original-resolution images decode with ImageIO",
                      "Every image retains its original pixel dimensions",
                      "103 image files and registration manifest match the verified v1.1.4 bytes"]
        } else {
            let snapshots = URL(fileURLWithPath: CommandLine.arguments[2])
            for index in 0..<16 {
                let url = snapshots.appendingPathComponent(String(format: "gaze-%02d.png", index))
                guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
                    throw NSError(domain: "AssetRegression", code: 3)
                }
                let feet = frames["look"]![index]["registrationFeet"] as! [Double]
                let top = Int(ceil(feet[1] / 208 * Double(bitmap.pixelsHigh))) + 1
                var left = bitmap.pixelsWide, right = 0, bottom = 0
                for y in top..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 64.0/255 {
                        left = min(left, x); right = max(right, x+1); bottom = max(bottom, y+1)
                    }
                }
                try require(right > left && bottom > top, "Missing visible feet in gaze \(index)")
                try require(bitmap.pixelsWide >= 384 && bitmap.pixelsHigh >= 416, "Native Retina snapshot lost resolution")
                measurements.append(["index":index,"width":right-left,"centerX":Double(left+right)/2,"baseline":bottom])
            }
            let widths = measurements.map { $0["width"] as! Int }
            let centers = measurements.map { $0["centerX"] as! Double }
            let bottoms = measurements.map { $0["baseline"] as! Int }
            try require(widths.max()!-widths.min()! <= 2, "Gaze body size changes in native rendering")
            try require(centers.max()!-centers.min()! <= 1, "Gaze body anchor shifts")
            try require(bottoms.max()!-bottoms.min()! <= 1, "Gaze floor position changes")
            checks = ["All 16 actual gaze snapshots preserve Retina pixel dimensions",
                      "Gaze body widths agree within two physical pixels",
                      "Gaze horizontal anchors agree within one physical pixel",
                      "Gaze baselines agree within one physical pixel"]
        }
        let result: [String: Any] = ["ok":true,"checks":checks,"measurements":measurements]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
