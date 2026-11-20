#ifndef SWIFT_COMPILER_COMPLETION_RANKING_H
#define SWIFT_COMPILER_COMPLETION_RANKING_H

#include <string_view>

namespace swift_toolchain {

/// SourceKit's ordering groups of completion results, from least to most preferred.
enum class CompletionBucket {
  NotRecommended,
  Normal,
  Literal,
  NormalTypeMatch,
  LiteralTypeMatch,
  HighPriorityKeyword,
  Operator,
  ExpressionSpecific,
  ExactMatch,
};

/// The values that order one completion result in the list that the completion backend returns.
///
/// The backend computes them from the compiler's result. The ranking itself needs no compiler, so
/// the contract tests check it directly.
struct CompletionRank {
  /// The filter name, which orders results that tie on every score.
  std::string_view name;
  /// The group, including SourceKit's meta groups such as an exact match.
  CompletionBucket bucket;
  /// The group without the meta groups, which orders results within one meta group.
  CompletionBucket baseBucket;
  /// The normalized fuzzy-match score from zero to one, or zero for a list without a filter.
  double matchScore;
  /// The weighted sum of the match score and the semantic context score.
  double score;
};

/// Returns the base name of a completion's filter name.
///
/// A function's filter name lists its argument labels. For example, the base name of
/// `print(_:separator:terminator:)` is `print`.
///
/// \param filterName The compiler's filter name of the result.
std::string_view completionBaseName(std::string_view filterName);

/// Returns whether a typed filter is the base name of a result, ignoring ASCII case.
///
/// \param filterName The compiler's filter name of the result.
/// \param filter The identifier prefix that the person typed.
bool completionMatchesExactly(std::string_view filterName, std::string_view filter);

/// Returns whether one result precedes another in a completion list.
///
/// Without a filter, the groups decide first, then the score, then the name. With a filter, exact
/// matches come first and results that are not recommended come last. Between them, a better
/// fuzzy match comes first, and the groups decide between equal matches. The backend sorts by
/// this order before it cuts the list to the requested size.
///
/// \param a The first result.
/// \param b The second result.
/// \param filtering Whether the person typed a filter.
bool completionRanksBefore(const CompletionRank &a, const CompletionRank &b, bool filtering);

} // namespace swift_toolchain

#endif
