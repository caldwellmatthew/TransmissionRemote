import Testing
import Foundation
@testable import TransmissionRemote

@Suite("Endpoint Parsing")
struct EndpointParsingTests {

    // MARK: - Unconfigured input falls back to the localhost default

    @Test func nilUsesDefault() {
        #expect(TransmissionClient.parseEndpoint(nil) == TransmissionClient.defaultEndpoint)
    }

    @Test func emptyUsesDefault() {
        #expect(TransmissionClient.parseEndpoint("") == TransmissionClient.defaultEndpoint)
    }

    @Test func whitespaceOnlyUsesDefault() {
        #expect(TransmissionClient.parseEndpoint("  \n") == TransmissionClient.defaultEndpoint)
    }

    // MARK: - Full URLs

    @Test func fullURLGetsRPCPath() {
        let url = TransmissionClient.parseEndpoint("http://server:9091")
        #expect(url?.absoluteString == "http://server:9091/transmission/rpc")
    }

    @Test func httpsPreserved() {
        let url = TransmissionClient.parseEndpoint("https://server:9091")
        #expect(url?.absoluteString == "https://server:9091/transmission/rpc")
    }

    @Test func trailingSlashTrimmed() {
        let url = TransmissionClient.parseEndpoint("http://server:9091/")
        #expect(url?.absoluteString == "http://server:9091/transmission/rpc")
    }

    @Test func existingRPCPathNotDuplicated() {
        let url = TransmissionClient.parseEndpoint("http://server:9091/transmission/rpc")
        #expect(url?.absoluteString == "http://server:9091/transmission/rpc")
    }

    // MARK: - Scheme-less input gets http:// prepended

    @Test func bareHostGetsScheme() {
        let url = TransmissionClient.parseEndpoint("server")
        #expect(url?.absoluteString == "http://server/transmission/rpc")
    }

    @Test func hostAndPortGetsScheme() {
        let url = TransmissionClient.parseEndpoint("192.168.1.5:9091")
        #expect(url?.absoluteString == "http://192.168.1.5:9091/transmission/rpc")
    }

    @Test func localhostAndPortGetsScheme() {
        // "localhost:9091" parses as scheme "localhost" without the prepend fix
        let url = TransmissionClient.parseEndpoint("localhost:9091")
        #expect(url?.absoluteString == "http://localhost:9091/transmission/rpc")
    }

    // MARK: - Unparseable input returns nil, never a silent localhost fallback

    @Test func schemeOnlyIsNil() {
        #expect(TransmissionClient.parseEndpoint("http://") == nil)
    }

    @Test func hostWithSpaceIsNil() {
        #expect(TransmissionClient.parseEndpoint("http://bad host") == nil)
    }
}
