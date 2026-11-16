import Foundation
import XCTest
@testable import T2PCore

final class MessagesTests: XCTestCase {
    func testCodes() {
        XCTAssertEqual(RoomCode.normalize(" ab-c d "), "ABCD")
        XCTAssertNil(RoomCode.normalize("AB0D"), "0 is a lookalike and isn't used")
        XCTAssertNil(RoomCode.normalize("ABCDE"))
        XCTAssertEqual(RoomCode.fromLink(URL(string: "https://time2play.live/k7qp")!), "K7QP")
        XCTAssertNil(RoomCode.fromLink(URL(string: "https://example.com/K7QP")!))
    }

    func testEncodesWithT() throws {
        let data = try JSONEncoder().encode(ClientMessage.join(name: "Sam", face: "fox"))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: String]
        XCTAssertEqual(obj, ["t": "join", "name": "Sam", "face": "fox"])
    }

    func testOldAppSurvivesNewServer() throws {
        let d = JSONDecoder()
        XCTAssertEqual(try d.decode(ServerMessage.self, from: Data(#"{"t":"welcome","min":1}"#.utf8)), .welcome(minVersion: 1))
        XCTAssertEqual(try d.decode(ServerMessage.self, from: Data(#"{"t":"welcome","min":9}"#.utf8)), .pleaseUpdate)
        XCTAssertEqual(try d.decode(ServerMessage.self, from: Data(#"{"t":"tournament","x":1}"#.utf8)), .unknown("tournament"))
    }
}
