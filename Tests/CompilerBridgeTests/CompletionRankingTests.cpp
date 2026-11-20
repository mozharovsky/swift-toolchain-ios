#include "CompletionRanking.h"
#include <algorithm>
#include <cstdio>
#include <string_view>
#include <vector>

using swift_toolchain::CompletionBucket;
using swift_toolchain::CompletionRank;

namespace {

/// A failed expectation remains visible even when release builds define NDEBUG.
int failures = 0;

/// CTest receives a nonzero exit status after every failed expectation is reported.
void expect(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    ++failures;
  }
}

/// Sorts results as the backend does and keeps the first `limit` names.
std::vector<std::string_view> ranked(std::vector<CompletionRank> results, bool filtering,
                                     size_t limit) {
  std::stable_sort(results.begin(), results.end(),
                   [filtering](const CompletionRank &a, const CompletionRank &b) {
                     return swift_toolchain::completionRanksBefore(a, b, filtering);
                   });
  std::vector<std::string_view> names;
  for (const CompletionRank &result : results) {
    if (names.size() == limit) {
      break;
    }
    names.push_back(result.name);
  }
  return names;
}

/// A function's argument labels never keep its base name from matching a typed filter.
void checkExactMatches() {
  expect(swift_toolchain::completionBaseName("print(_:separator:terminator:)") == "print",
         "The base name must drop the argument labels.");
  expect(swift_toolchain::completionBaseName("count") == "count",
         "A property's filter name is its base name.");
  expect(swift_toolchain::completionMatchesExactly("print(_:separator:terminator:)", "print"),
         "A filter that names a function must match it exactly.");
  expect(swift_toolchain::completionMatchesExactly("Text(_:)", "text"),
         "An exact match must ignore ASCII case.");
  expect(!swift_toolchain::completionMatchesExactly("print(_:separator:terminator:)", "pri"),
         "A prefix must not match exactly.");
  expect(!swift_toolchain::completionMatchesExactly("printer", "print"),
         "A longer base name must not match exactly.");
  expect(!swift_toolchain::completionMatchesExactly("(_:)", ""),
         "An empty filter must not match exactly.");
}

/// A typed prefix of `print` inside a view body must keep `print` when many views match loosely.
void checkFilteredCut() {
  std::vector<CompletionRank> results;
  for (std::string_view name : {"ProgressView", "Picker", "PrimitiveButtonStyle", "ProposedSize"}) {
    results.push_back(
        {name, CompletionBucket::NormalTypeMatch, CompletionBucket::NormalTypeMatch, 4.0});
  }
  results.push_back({"print(_:separator:terminator:to:)", CompletionBucket::Normal,
                     CompletionBucket::Normal, 9.5});
  results.push_back(
      {"print(_:separator:terminator:)", CompletionBucket::Normal, CompletionBucket::Normal, 9.6});
  results.push_back({"precondition(_:_:file:line:)", CompletionBucket::NotRecommended,
                     CompletionBucket::Normal, 12.0});

  const auto filtered = ranked(results, true, 3);
  expect(filtered.size() == 3 && filtered[0] == "print(_:separator:terminator:)" &&
             filtered[1] == "print(_:separator:terminator:to:)",
         "A filtered list must put better matches first and keep them through the cut.");
  const auto all = ranked(results, true, results.size());
  expect(all.back() == "precondition(_:_:file:line:)",
         "A filtered list must rank a result that is not recommended last.");
  const auto unfiltered = ranked(results, false, 1);
  expect(unfiltered.size() == 1 && unfiltered[0] != "print(_:separator:terminator:)",
         "A list without a filter must keep the groups first.");
}

/// An exact match outranks a higher score, and equal scores fall back to the groups.
void checkTiers() {
  const CompletionRank exact{"print(_:separator:terminator:)", CompletionBucket::ExactMatch,
                             CompletionBucket::Normal, 6.0};
  const CompletionRank closer{"printed", CompletionBucket::Normal, CompletionBucket::Normal, 10.0};
  expect(swift_toolchain::completionRanksBefore(exact, closer, true),
         "An exact match must precede every other match.");
  const CompletionRank typed{"Text", CompletionBucket::NormalTypeMatch,
                             CompletionBucket::NormalTypeMatch, 8.0};
  const CompletionRank untyped{"text", CompletionBucket::Normal, CompletionBucket::Normal, 8.0};
  expect(swift_toolchain::completionRanksBefore(typed, untyped, true),
         "Equal scores must leave the order to the groups.");
  const CompletionRank first{"alpha", CompletionBucket::Normal, CompletionBucket::Normal, 9.0};
  const CompletionRank second{"Beta", CompletionBucket::Normal, CompletionBucket::Normal, 9.0};
  expect(swift_toolchain::completionRanksBefore(first, second, true) &&
             !swift_toolchain::completionRanksBefore(second, first, true) &&
             !swift_toolchain::completionRanksBefore(first, first, true),
         "Equal scores must order names without case and stay irreflexive.");
}

/// A local name on `co` precedes a global name whose match is slightly closer.
void checkSemanticContext() {
  const CompletionRank local{"config", CompletionBucket::Normal, CompletionBucket::Normal,
                             swift_toolchain::completionScore(0.70, 0.875)};
  const CompletionRank global{"Color", CompletionBucket::Normal, CompletionBucket::Normal,
                              swift_toolchain::completionScore(0.75, 0.1875)};
  expect(swift_toolchain::completionRanksBefore(local, global, true),
         "A local name must precede a global name with a slightly closer match.");
  const CompletionRank distant{"Codable", CompletionBucket::Normal, CompletionBucket::Normal,
                               swift_toolchain::completionScore(1.0, 0.1875)};
  const CompletionRank loose{"accountColor", CompletionBucket::Normal, CompletionBucket::Normal,
                             swift_toolchain::completionScore(0.2, 0.875)};
  expect(swift_toolchain::completionRanksBefore(distant, loose, true),
         "A much closer match must precede a local name.");
}

/// An exact match that is not recommended survives the cut after the recommended exact matches.
void checkNotRecommendedExactMatch() {
  using swift_toolchain::completionBucket;
  expect(completionBucket(CompletionBucket::Normal, true) == CompletionBucket::ExactMatch &&
             completionBucket(CompletionBucket::ExpressionSpecific, true) ==
                 CompletionBucket::ExactMatch &&
             completionBucket(CompletionBucket::NotRecommended, true) ==
                 CompletionBucket::ExactMatch,
         "An exact match must move every result into the exact-match group.");
  expect(completionBucket(CompletionBucket::Normal, false) == CompletionBucket::Normal,
         "A result without an exact match must keep its group.");

  std::vector<CompletionRank> results;
  for (std::string_view name : {"printer", "printed", "printLog(_:)"}) {
    results.push_back(
        {name, completionBucket(CompletionBucket::Normal, false), CompletionBucket::Normal, 20.0});
  }
  results.push_back({"print(_:)", completionBucket(CompletionBucket::NotRecommended, true),
                     CompletionBucket::Normal, 19.0, true});
  results.push_back({"print(_:separator:terminator:)",
                     completionBucket(CompletionBucket::Normal, true), CompletionBucket::Normal,
                     18.0});
  results.push_back({"print(_:separator:terminator:to:)",
                     completionBucket(CompletionBucket::Normal, true), CompletionBucket::Normal,
                     17.0});

  const auto filtered = ranked(results, true, 3);
  expect(filtered.size() == 3 && filtered[0] == "print(_:separator:terminator:)" &&
             filtered[1] == "print(_:separator:terminator:to:)" && filtered[2] == "print(_:)",
         "An exact match that is not recommended must survive the cut after the recommended exact "
         "matches.");
}

/// A keyword without high priority scores as a declaration from an imported module.
void checkKeywordSemanticScore() {
  using swift_toolchain::CompletionKeyword;
  using swift_toolchain::CompletionSemanticContext;
  using swift_toolchain::completionSemanticScore;
  const double imported = completionSemanticScore(CompletionSemanticContext::OtherModule,
                                                  CompletionKeyword::NotKeyword);
  expect(completionSemanticScore(CompletionSemanticContext::None, CompletionKeyword::Keyword) ==
             imported,
         "A keyword must not score above a declaration from an imported module.");
  expect(completionSemanticScore(CompletionSemanticContext::None,
                                 CompletionKeyword::HighPriorityKeyword) > imported,
         "A high-priority keyword must score above a declaration from an imported module.");
  expect(completionSemanticScore(CompletionSemanticContext::None, CompletionKeyword::NotKeyword) ==
             0.0,
         "A result without a semantic context must score zero unless it is a keyword.");
}

/// The compiler's flags scale the score by the factors of sourcekit-lsp's `CompletionScoring`.
void checkFlair() {
  using swift_toolchain::CompletionFlair;
  using swift_toolchain::completionScore;
  const double plain = completionScore(0.5, 0.5);
  CompletionFlair common;
  common.commonKeywordAtCurrentPosition = true;
  CompletionFlair rare;
  rare.rareKeywordAtCurrentPosition = true;
  rare.rareTypeAtCurrentPosition = true;
  CompletionFlair invalid;
  invalid.expressionAtNonScriptOrMainFileScope = true;
  expect(completionScore(0.5, 0.5, common) == plain * 1.25,
         "A common keyword must gain a quarter of its score.");
  expect(completionScore(0.5, 0.5, rare) == plain * 0.75 * 0.75,
         "Each rare flag must keep three quarters of the score.");
  expect(completionScore(0.5, 0.5, invalid) == plain * 0.125,
         "A statement at the top level of a library file must keep an eighth of its score.");
}

/// One candidate of the typed `print` check with its normalized fuzzy-match score.
struct TypedCandidate {
  /// The compiler's filter name.
  std::string_view name;
  /// The score of the pinned `FuzzyStringMatcher` with normalization for the typed filter.
  double match;
  /// Whether the result is a keyword. Only a keyword gets a rare flag in a function body.
  bool keyword;
};

/// Ranks the typed candidates in a function body or at the top level of `main.swift`.
///
/// In a function body, the compiler marks each of these keywords as rare. At the top level of
/// `main.swift`, it sets no flags.
std::vector<std::string_view> rankedTyped(const std::vector<TypedCandidate> &candidates,
                                          bool functionBody) {
  using swift_toolchain::CompletionKeyword;
  using swift_toolchain::CompletionSemanticContext;
  std::vector<CompletionRank> results;
  for (const TypedCandidate &candidate : candidates) {
    swift_toolchain::CompletionFlair flair;
    flair.rareKeywordAtCurrentPosition = functionBody && candidate.keyword;
    const double semantic =
        candidate.keyword
            ? swift_toolchain::completionSemanticScore(CompletionSemanticContext::None,
                                                       CompletionKeyword::Keyword)
            : swift_toolchain::completionSemanticScore(CompletionSemanticContext::OtherModule,
                                                       CompletionKeyword::NotKeyword);
    results.push_back({candidate.name, CompletionBucket::Normal, CompletionBucket::Normal,
                       swift_toolchain::completionScore(candidate.match, semantic, flair)});
  }
  return ranked(results, true, results.size());
}

/// `print` comes first on `pri` and within the first two results on `pr` against the matching
/// declaration keywords.
///
/// The match scores come from the pinned `FuzzyStringMatcher`. A function matches at least as well
/// as its base name. `print` therefore carries the score of `print` alone.
void checkTypedPrint() {
  const std::vector<TypedCandidate> pri{
      {"private", 0.898038, true},
      {"print(_:separator:terminator:)", 0.901354, false},
  };
  const std::vector<TypedCandidate> pr{
      {"prefix", 0.886644, true},
      {"private", 0.885041, true},
      {"protocol", 0.883838, true},
      {"precedencegroup", 0.879910, true},
      {"print(_:separator:terminator:)", 0.888889, false},
  };
  for (bool functionBody : {true, false}) {
    const auto onPri = rankedTyped(pri, functionBody);
    expect(onPri.front() == "print(_:separator:terminator:)",
           functionBody ? "`print` must come first on `pri` in a function body."
                        : "`print` must come first on `pri` at the top level of main.swift.");
    const auto onPr = rankedTyped(pr, functionBody);
    expect(std::find(onPr.begin(), onPr.begin() + 2, "print(_:separator:terminator:)") !=
               onPr.begin() + 2,
           functionBody ? "`print` must be among the first two results on `pr` in a function body."
                        : "`print` must be among the first two results on `pr` at the top level of "
                          "main.swift.");
  }
}

} // namespace

int main() {
  checkExactMatches();
  checkFilteredCut();
  checkTiers();
  checkSemanticContext();
  checkNotRecommendedExactMatch();
  checkKeywordSemanticScore();
  checkFlair();
  checkTypedPrint();
  return failures == 0 ? 0 : 1;
}
