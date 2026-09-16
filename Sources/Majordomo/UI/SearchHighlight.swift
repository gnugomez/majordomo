// Search-match highlighting: the environment carries the active search's
// terms, and every text-rendering view paints its occurrences with the
// system find highlight.

import SwiftUI

extension EnvironmentValues {
  /// The active search's terms; empty when no search is running.
  @Entry var searchHighlightTerms: [String] = []
}

/// A query's terms — the unit the filter and the highlighters share.
func searchTerms(_ query: String) -> [String] {
  query.split(whereSeparator: \.isWhitespace).map(String.init)
}

func highlighted(_ text: String, terms: [String]) -> AttributedString {
  highlighted(AttributedString(text), terms: terms)
}

/// Paints the find highlight over every term occurrence, matching the way
/// the search filter matches (case- and diacritic-insensitive).
func highlighted(_ text: AttributedString, terms: [String]) -> AttributedString {
  guard !terms.isEmpty else { return text }
  var result = text
  let plain = String(text.characters)
  for term in terms {
    var searchFrom = plain.startIndex
    while searchFrom < plain.endIndex,
          let match = plain.range(
            of: term, options: [.caseInsensitive, .diacriticInsensitive],
            range: searchFrom ..< plain.endIndex
          ) {
      if let range = Range(NSRange(match, in: plain), in: result) {
        result[range].backgroundColor = Color(nsColor: .findHighlightColor)
        // The find highlight stays yellow in dark mode; fix the text color
        // so matches stay legible on it (and on selected rows).
        result[range].foregroundColor = .black
      }
      searchFrom = match.upperBound
    }
  }
  return result
}
