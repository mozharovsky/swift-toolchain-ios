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

/// The compiler's semantic context of a result, from the nearest declaration to no declaration.
enum class CompletionSemanticContext {
  Local,
  CurrentNominal,
  Super,
  OutsideNominal,
  CurrentModule,
  OtherModule,
  None,
};

/// The kind of keyword that a result inserts.
///
/// It decides the semantic context score of a result without a semantic context.
enum class CompletionKeyword {
  NotKeyword,
  /// A statement, expression, or type-introducing keyword, such as `switch`, `await`, or `struct`.
  ///
  /// SourceKit's high-priority keywords, such as `let` and `func`, also belong here.
  Keyword,
  /// Any other declaration keyword or a modifier, such as `private`, `import`, or `prefix`.
  DeclarationKeyword,
};

/// The compiler's flags that make a result more or less likely at the completion position.
struct CompletionFlair {
  /// A keyword that often starts a declaration here, such as `struct` at the top level of a
  /// library file.
  bool commonKeywordAtCurrentPosition = false;
  /// A keyword that rarely fits here, such as `private` in a function body.
  bool rareKeywordAtCurrentPosition = false;
  /// A type that rarely fits here, such as a protocol name in an expression.
  bool rareTypeAtCurrentPosition = false;
  /// A declaration that would start a statement at the top level of a library file.
  ///
  /// Only `main.swift` and scripts allow top-level statements.
  bool expressionAtNonScriptOrMainFileScope = false;
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
  /// The score from `completionScore`.
  double score;
  /// Whether the compiler marks the result as not recommended or its type as invalid.
  ///
  /// An exact match keeps this mark in the exact-match group, after the recommended exact matches.
  bool notRecommended = false;
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

/// Returns the semantic context score from zero for a global name to one for a local name.
///
/// The score follows SourceKit's table without import-depth data. A result without a semantic
/// context scores zero unless it is a keyword. A `Keyword` scores between the current module and an
/// imported module, as in SourceKit. A `DeclarationKeyword` scores as a declaration from an
/// imported module. A closer match of such a declaration therefore precedes it.
double completionSemanticScore(CompletionSemanticContext context, CompletionKeyword keyword);

/// Returns the ranking score of a result.
///
/// The match weighs more than the semantic context. The compiler's flags then scale the weighted
/// sum. For example, a rare keyword keeps three quarters of its score. See `completionRanksBefore`.
///
/// \param matchScore The normalized fuzzy-match score from zero to one, or zero without a filter.
/// \param semanticScore The score from `completionSemanticScore`.
/// \param flair The compiler's flags for the result at the completion position.
double completionScore(double matchScore, double semanticScore, const CompletionFlair &flair = {});

/// Returns the group of a result once an exact match is known.
///
/// The backend calls it for the group that includes SourceKit's other meta groups. An exact match
/// moves every result into the exact-match group, as in SourceKit. A result that is not recommended
/// then follows the recommended exact matches. See `CompletionRank.notRecommended`.
///
/// \param group The result's group, which may be `NotRecommended` or `ExpressionSpecific`.
/// \param exactMatch Whether the typed filter is the result's base name.
CompletionBucket completionBucket(CompletionBucket group, bool exactMatch);

/// Returns whether one result precedes another in a completion list.
///
/// Without a filter, the groups decide first, then the score, then the name. With a filter, exact
/// matches come first and results that are not recommended come last. Recommended results precede
/// the others within the exact matches. Then the higher score comes first, and the groups decide
/// between equal scores. The backend sorts by this order before it cuts the list to the requested
/// size.
///
/// \param a The first result.
/// \param b The second result.
/// \param filtering Whether the person typed a filter.
bool completionRanksBefore(const CompletionRank &a, const CompletionRank &b, bool filtering);

} // namespace swift_toolchain

#endif
