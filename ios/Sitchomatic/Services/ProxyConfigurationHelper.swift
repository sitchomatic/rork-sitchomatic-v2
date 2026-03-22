import Foundation
import WebKit
import Network

@MainActor
enum ProxyConfigurationHelper {

    static func applyProxyConfiguration(
        to dataStore: WKWebsiteDataStore,
        endpoint: ProxyEndpoint?
    ) {
        guard let endpoint else {
            dataStore.proxyConfigurations = []
            return
        }

        let host = NWEndpoint.Host(endpoint.host)
        guard let port = NWEndpoint.Port(rawValue: UInt16(endpoint.port)) else {
            dataStore.proxyConfigurations = []
            return
        }

        let nwEndpoint = NWEndpoint.hostPort(host: host, port: port)
        let proxyConfig = ProxyConfiguration(socksv5Proxy: nwEndpoint)

        if let username = endpoint.username, let password = endpoint.password,
           !username.isEmpty, !password.isEmpty {
            proxyConfig.applyCredential(username: username, password: password)
        }

        dataStore.proxyConfigurations = [proxyConfig]
    }

    static func configuredWebViewConfiguration(
        forSessionID sessionID: String,
        networkManager: SimpleNetworkManager = .shared
    ) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true

        let dataStore = WKWebsiteDataStore.nonPersistent()
        let proxyEndpoint = networkManager.proxyEndpoint(forSessionID: sessionID)
        applyProxyConfiguration(to: dataStore, endpoint: proxyEndpoint)
        config.websiteDataStore = dataStore

        return config
    }

    static func configuredDataStore(
        forSessionID sessionID: String,
        networkManager: SimpleNetworkManager = .shared
    ) -> WKWebsiteDataStore {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let proxyEndpoint = networkManager.proxyEndpoint(forSessionID: sessionID)
        applyProxyConfiguration(to: dataStore, endpoint: proxyEndpoint)
        return dataStore
    }
}
