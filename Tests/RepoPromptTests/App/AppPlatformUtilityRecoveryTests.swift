@testable import RepoPrompt
import XCTest

final class AppPlatformUtilityRecoveryTests: XCTestCase {
    func testAgentSessionDeepLinkURLRoundTripsAndRejectsInvalidScopedRoutes() throws {
        let route = try AgentSessionDeepLinkRoute(
            windowID: 7,
            workspaceID: XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            tabID: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            sessionID: XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        )

        XCTAssertEqual(AppDeepLinkRoute.parse(url: route.url), .route(.agentSession(route)))

        let missingWorkspace = try XCTUnwrap(URL(string: "repoprompt://agent/session?tab_id=\(route.tabID.uuidString)"))
        let malformedSession = try XCTUnwrap(URL(string: "repoprompt://agent/session?workspace_id=\(route.workspaceID.uuidString)&tab_id=\(route.tabID.uuidString)&session_id=not-a-uuid"))
        let unsupportedAgentPath = try XCTUnwrap(URL(string: "repoprompt://agent/other?workspace_id=\(route.workspaceID.uuidString)&tab_id=\(route.tabID.uuidString)"))

        XCTAssertEqual(AppDeepLinkRoute.parse(url: missingWorkspace), .invalidScopedRoute)
        XCTAssertEqual(AppDeepLinkRoute.parse(url: malformedSession), .invalidScopedRoute)
        XCTAssertEqual(AppDeepLinkRoute.parse(url: unsupportedAgentPath), .invalidScopedRoute)
    }

    func testAppcastParserSelectsHighestInlineVersionAndKeepsMetadata() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        	<channel>
        		<item>
        			<title>Version 2.1.9</title>
        			<sparkle:shortVersionString>2.1.9</sparkle:shortVersionString>
        			<sparkle:version>319</sparkle:version>
        			<enclosure url="https://example.com/RepoPrompt-2.1.9.zip" />
        		</item>
        		<item>
        			<title>Version 2.1.20</title>
        			<sparkle:shortVersionString>2.1.20</sparkle:shortVersionString>
        			<sparkle:version>320</sparkle:version>
        			<pubDate>Tue, 21 Apr 2026 12:28:34 +0000</pubDate>
        			<sparkle:releaseNotesLink>https://example.com/release-notes.html</sparkle:releaseNotesLink>
        			<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        			<enclosure url="https://example.com/RepoPrompt-2.1.20.zip" />
        		</item>
        	</channel>
        </rss>
        """

        let version = try XCTUnwrap(AppcastParser().parse(data: Data(xml.utf8)))

        XCTAssertEqual(version.version, "2.1.20")
        XCTAssertEqual(version.buildNumber, "320")
        XCTAssertEqual(version.releaseNotesURL, "https://example.com/release-notes.html")
        XCTAssertEqual(version.downloadURL, "https://example.com/RepoPrompt-2.1.20.zip")
        XCTAssertEqual(version.minimumSystemVersion, "14.0")
        XCTAssertNotNil(version.date)
    }
}
