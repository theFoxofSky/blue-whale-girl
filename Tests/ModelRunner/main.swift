import Foundation

let checks = runModelTests()
let data = try JSONSerialization.data(withJSONObject: ["ok": true, "checks": checks],
                                      options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
