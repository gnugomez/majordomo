// The exchange behind a provider error, as text: the status and address,
// the headers in order with no cookie, the body laid out, long ones cut
// short, and a request nothing answered.

import Foundation
import Testing
@testable import Majordomo

@Suite("Error transcripts")
struct TranscriptTests {
  private let url = URL(string: "https://api.github.com/user")!

  private func answer(_ status: Int, headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
  }

  @Test func anAnswerReadsStatusAddressHeadersAndBody() {
    let http = answer(401, headers: [
      "X-RateLimit-Remaining": "4999", "Content-Type": "application/json", "Set-Cookie": "session=secret",
    ])
    let body = Data(#"{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest"}"#.utf8)
    let text = transcript(of: http, body: body)
    let lines = text.components(separatedBy: "\n")
    #expect(lines[0] == "HTTP 401 Unauthorized")
    #expect(lines[1] == url.absoluteString)
    #expect(lines[2] == "")
    #expect(lines[3] == "content-type: application/json")
    #expect(lines[4] == "x-ratelimit-remaining: 4999")
    #expect(!text.contains("secret"))
    #expect(text.hasSuffix("""
    {
      "documentation_url" : "https://docs.github.com/rest",
      "message" : "Bad credentials"
    }
    """))
  }

  @Test func aBodyThatIsNotJSONComesAsItIs() {
    #expect(bodyText(Data("<html>nope</html>".utf8)) == "<html>nope</html>")
    #expect(bodyText(Data()) == "(empty body)")
  }

  @Test func aLongBodyIsCutShort() {
    let text = bodyText(Data(String(repeating: "x", count: 40_000).utf8))
    #expect(text.hasSuffix("… (8000 more characters)"))
    #expect(text.count < 32_100)
  }

  @Test func aStatusErrorCarriesTheAnswer() {
    let ctx = RequestContext(service: "GitHub", origin: "https://api.github.com", originIsUserSupplied: false)
    let error = statusError(answer(403, headers: [:]), Data("{}".utf8), ctx)
    #expect(error.message.contains("403"))
    #expect(!error.rejectsToken)
    #expect(error.details?.hasPrefix("HTTP 403 Forbidden\n\(url.absoluteString)\n\n{") == true)
  }

  @Test func aRequestNothingAnsweredNamesItAndTheFailureButNoHeader() {
    var request = URLRequest(url: url)
    request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
    let text = transportTranscript(request, URLError(.cannotFindHost))
    #expect(text.hasPrefix("GET \(url.absoluteString)\n\n"))
    #expect(text.contains("NSURLErrorDomain -1003"))
    #expect(!text.contains("secret"))
  }
}
