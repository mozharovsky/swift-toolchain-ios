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
  /// The weighted sum of the fuzzy-match score and the semantic context score.
  ///
  /// See `completionScore`.
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

/// Returns the score that orders filtered results between the exact matches and the results that
/// are not recommended.
///
/// The match weighs more than the semantic context.
///
/// \param matchScore The normalized fuzzy-match score from zero to one, or zero without a filter.
/// \param semanticScore The semantic context score from zero for a global name to one for a local
/// name.
double completionScore(double matchScore, double semanticScore);

/// Returns the group of a result once an exact match is known.
///
/// The backend calls it for the group that includes SourceKit's other meta groups. An exact match
/// moves a result into the exact-match group. A result that is not recommended stays in its group
/// even when it matches exactly. A recommended result therefore precedes it.
///
/// \param group The result's group, which may be `NotRecommended` or `ExpressionSpecific`.
/// \param exactMatch Whether the typed filter is the result's base name.
CompletionBucket completionBucket(CompletionBucket group, bool exactMatch);

/// Returns whether one result precedes another in a completion list.
///
/// Without a filter, the groups decide first, then the score, then the name. With a filter, exact
/// matches come first and results that are not recommended come last. Between them, the higher
/// score comes first, and the groups decide between equal scores. The backend sorts by this order
/// before it cuts the list to the requested size.
///
/// \param a The first result.
/// \param b The second result.
/// \param filtering Whether the person typed a filter.
bool completionRanksBefore(const CompletionRank &a, const CompletionRank &b, bool filtering);

} // namespace swift_toolchain

#endif
