import Testing
import Foundation

@Test func infoPlistDeclaresHealthUsageAndAppGroup() {
    let info = Bundle.main.infoDictionary ?? [:]
    #expect((info["CFBundleDisplayName"] as? String) == "Forme du jour")
    #expect(((info["NSHealthShareUsageDescription"] as? String) ?? "").isEmpty == false)
    #expect(((info["NSHealthUpdateUsageDescription"] as? String) ?? "").isEmpty == false)
    #expect(((info["AppGroupIdentifier"] as? String) ?? "").hasPrefix("group."))
}
