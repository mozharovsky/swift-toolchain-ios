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
        {name, CompletionBucket::NormalTypeMatch, CompletionBucket::NormalTypeMatch, 0.2, 4.0});
  }
  results.push_back({"print(_:separator:terminator:to:)", CompletionBucket::Normal,
                     CompletionBucket::Normal, 0.71, 9.5});
  results.push_back({"print(_:separator:terminator:)", CompletionBucket::Normal,
                     CompletionBucket::Normal, 0.72, 9.6});
  results.push_back({"precondition(_:_:file:line:)", CompletionBucket::NotRecommended,
                     CompletionBucket::Normal, 0.9, 12.0});

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

/// An exact match outranks a closer fuzzy score, and equal scores fall back to the groups.
void checkTiers() {
  const CompletionRank exact{"print(_:separator:terminator:)", CompletionBucket::ExactMatch,
                             CompletionBucket::Normal, 0.5, 6.0};
  const CompletionRank closer{"printed", CompletionBucket::Normal, CompletionBucket::Normal, 0.8,
                              10.0};
  expect(swift_toolchain::completionRanksBefore(exact, closer, true),
         "An exact match must precede every other match.");
  const CompletionRank typed{"Text", CompletionBucket::NormalTypeMatch,
                             CompletionBucket::NormalTypeMatch, 0.6, 8.0};
  const CompletionRank untyped{"text", CompletionBucket::Normal, CompletionBucket::Normal, 0.6,
                               9.0};
  expect(swift_toolchain::completionRanksBefore(typed, untyped, true),
         "Equal match scores must leave the order to the groups.");
  const CompletionRank first{"alpha", CompletionBucket::Normal, CompletionBucket::Normal, 0.6, 9.0};
  const CompletionRank second{"Beta", CompletionBucket::Normal, CompletionBucket::Normal, 0.6, 9.0};
  expect(swift_toolchain::completionRanksBefore(first, second, true) &&
             !swift_toolchain::completionRanksBefore(second, first, true) &&
             !swift_toolchain::completionRanksBefore(first, first, true),
         "Equal scores must order names without case and stay irreflexive.");
}

} // namespace

int main() {
  checkExactMatches();
  checkFilteredCut();
  checkTiers();
  return failures == 0 ? 0 : 1;
}
