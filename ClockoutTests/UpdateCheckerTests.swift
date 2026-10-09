import Foundation
import Testing
@testable import Clockout

/// Answers every request with the status and body set before the test.
private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func releaseJSON(tag: String, url: String = "https://github.com/\(UpdateChecker.repository)/releases/tag/v1.2", prerelease: Bool = false) -> Data {
    Data(#"{"tag_name": "\#(tag)", "html_url": "\#(url)", "draft": false, "prerelease": \#(prerelease)}"#.utf8)
}

@MainActor
@Suite(.serialized)
struct UpdateCheckerTests {
    private func makeChecker(_ name: String, version: String) -> UpdateChecker {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return UpdateChecker(defaults: defaults, session: URLSession(configuration: configuration), currentVersion: version)
    }

    @Test func comparesVersionNumbers() {
        #expect(UpdateChecker.isVersion("1.2", newerThan: "1.1"))
        #expect(UpdateChecker.isVersion("1.10", newerThan: "1.9"))
        #expect(UpdateChecker.isVersion("2", newerThan: "1.9.9"))
        #expect(!UpdateChecker.isVersion("1.1.0", newerThan: "1.1"))
        #expect(!UpdateChecker.isVersion("1.0", newerThan: "1.1"))
    }

    @Test func readsOnlyReleasesOfThisRepository() {
        #expect(UpdateChecker.release(from: releaseJSON(tag: "v1.2"))?.version == "1.2")
        #expect(UpdateChecker.release(from: releaseJSON(tag: "v1.2", url: "https://evil.example/releases")) == nil)
        #expect(UpdateChecker.release(from: releaseJSON(tag: "v1.2", url: "https://github.com/someone/else/releases/tag/v1.2")) == nil)
        #expect(UpdateChecker.release(from: releaseJSON(tag: "v1.2", prerelease: true)) == nil)
        #expect(UpdateChecker.release(from: releaseJSON(tag: "latest")) == nil)
        #expect(UpdateChecker.release(from: Data("not json".utf8)) == nil)
    }

    @Test func offersANewerReleaseUntilItIsSkipped() async {
        StubProtocol.status = 200
        StubProtocol.body = releaseJSON(tag: "v1.2")
        let checker = makeChecker("update-newer-tests", version: "1.1")
        await checker.check()
        #expect(checker.offeredRelease?.version == "1.2")

        if let release = checker.offeredRelease { checker.skip(release) }
        await checker.check()
        #expect(checker.offeredRelease == nil)
    }

    @Test func staysQuietWithoutNewerRelease() async {
        StubProtocol.status = 200
        StubProtocol.body = releaseJSON(tag: "v1.1")
        let current = makeChecker("update-same-tests", version: "1.1")
        await current.check()
        #expect(current.state == .upToDate)

        StubProtocol.status = 404
        StubProtocol.body = Data()
        let none = makeChecker("update-none-tests", version: "1.1")
        await none.check()
        #expect(none.state == .upToDate)

        StubProtocol.status = 500
        let failing = makeChecker("update-failing-tests", version: "1.1")
        await failing.check()
        #expect(failing.state == .failed)
    }
}
