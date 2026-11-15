import XCTest
@testable import IPVIOStream

final class ParserTests: XCTestCase {
    func testClassifiesLiveMoviesAndSeries() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-logo="http://l/a.png" group-title="News",BBC One
        http://h/live/u/p/1.ts
        #EXTINF:-1 group-title="Action",Alien (1979)
        http://h/movie/u/p/2.mkv
        #EXTINF:-1 group-title="Drama",Dark S01E02 Lies
        http://h/series/u/p/3.mkv
        #EXTINF:-1 group-title="Drama",Dark S01E01
        http://h/series/u/p/4.mkv
        #EXTINF:-1 group-title="Emby Live TV",5 Arte
        http://e/emby/Videos/9/master.m3u8?api_key=t&ipvio_live=1
        """
        let c = M3UParser.parse(m3u)
        XCTAssertEqual(c.live.map(\.title), ["BBC One", "5 Arte"])
        XCTAssertEqual(c.live.first?.logo?.absoluteString, "http://l/a.png")
        XCTAssertEqual(c.movies.first?.title, "Alien")
        XCTAssertEqual(c.movies.first?.year, "1979")
        XCTAssertEqual(c.series.count, 1)
        XCTAssertEqual(c.series.first?.episodes?.map(\.number), [1, 2])
        XCTAssertEqual(c.series.first?.episodes?.last?.title, "Lies")
    }

    func testEmbyAddressIsNormalised() {
        XCTAssertEqual(EmbyClient.normalized("192.168.1.20:8096/"), "http://192.168.1.20:8096")
        XCTAssertEqual(EmbyClient.normalized("https://media.example.com/web/index.html"), "https://media.example.com")
        XCTAssertEqual(EmbyClient.normalized("https://media.example.com/emby"), "https://media.example.com")
        XCTAssertEqual(EmbyClient.normalized("http://webserver.local:8096"), "http://webserver.local:8096")
        XCTAssertNil(EmbyClient.normalized("   "))
    }

    func testSplitYear() {
        XCTAssertEqual(M3UParser.splitYear("Alien (1979)").0, "Alien")
        XCTAssertNil(M3UParser.splitYear("Alien").1)
    }
}
