import Foundation

nonisolated struct NordServer: Sendable, Identifiable {
    let id: Int
    let hostname: String
    let ip: String
    let country: String
    let load: Int
    let publicKey: String
}

nonisolated struct NordAPIServerResponse: Codable, Sendable {
    let id: Int
    let name: String
    let hostname: String
    let load: Int
    let status: String
    let station: String
    let locations: [NordAPILocation]?
    let technologies: [NordAPITechnology]?

    func toNordServer() -> NordServer? {
        guard status == "online" else { return nil }
        let wgTech = technologies?.first { $0.identifier == "wireguard_udp" }
        let serverPublicKey = wgTech?.metadata?.first { $0.name == "public_key" }?.value ?? ""
        let countryCode = locations?.first?.country?.code ?? "??"
        return NordServer(
            id: id,
            hostname: hostname,
            ip: station,
            country: countryCode,
            load: load,
            publicKey: serverPublicKey
        )
    }
}

nonisolated struct NordAPILocation: Codable, Sendable {
    let country: NordAPICountry?
}

nonisolated struct NordAPICountry: Codable, Sendable {
    let id: Int?
    let name: String?
    let code: String?
}

nonisolated struct NordAPITechnology: Codable, Sendable {
    let id: Int?
    let identifier: String?
    let metadata: [NordAPIMetadata]?
}

nonisolated struct NordAPIMetadata: Codable, Sendable {
    let name: String?
    let value: String?
}
