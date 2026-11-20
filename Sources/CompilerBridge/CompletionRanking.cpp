#include "CompletionRanking.h"
#include <algorithm>
#include <cstddef>

namespace {

/// Lowers an ASCII letter and keeps every other byte, as LLVM's case-insensitive comparison does.
char lowered(char byte) {
  return byte >= 'A' && byte <= 'Z' ? static_cast<char>(byte - 'A' + 'a') : byte;
}

/// Compares two names ignoring ASCII case, with a prefix before the longer name.
///
/// \returns A negative value, zero, or a positive value, as `strcmp` does.
int compareInsensitive(std::string_view a, std::string_view b) {
  const size_t length = std::min(a.size(), b.size());
  for (size_t index = 0; index < length; ++index) {
    const char left = lowered(a[index]);
    const char right = lowered(b[index]);
    if (left != right) {
      return static_cast<unsigned char>(left) < static_cast<unsigned char>(right) ? -1 : 1;
    }
  }
  if (a.size() == b.size()) {
    return 0;
  }
  return a.size() < b.size() ? -1 : 1;
}

/// The part of a filtered list that a result belongs to, from last to first.
int filteredTier(swift_toolchain::CompletionBucket bucket) {
  switch (bucket) {
  case swift_toolchain::CompletionBucket::NotRecommended:
    return 0;
  case swift_toolchain::CompletionBucket::ExactMatch:
    return 2;
  default:
    return 1;
  }
}

/// Returns the factor that the compiler's flags apply to a score.
///
/// The factors are those of the `Flair` score component in the open `CompletionScoring` module of
/// sourcekit-lsp (`SemanticClassification.swift`).
double flairFactor(const swift_toolchain::CompletionFlair &flair) {
  double factor = 1.0;
  if (flair.commonKeywordAtCurrentPosition) {
    factor *= 1.25;
  }
  if (flair.rareKeywordAtCurrentPosition) {
    factor *= 0.75;
  }
  if (flair.rareTypeAtCurrentPosition) {
    factor *= 0.75;
  }
  if (flair.expressionAtNonScriptOrMainFileScope) {
    factor *= 0.125;
  }
  return factor;
}

} // namespace

std::string_view swift_toolchain::completionBaseName(std::string_view filterName) {
  return filterName.substr(0, filterName.find('('));
}

bool swift_toolchain::completionMatchesExactly(std::string_view filterName,
                                               std::string_view filter) {
  return !filter.empty() && compareInsensitive(completionBaseName(filterName), filter) == 0;
}

double swift_toolchain::completionSemanticScore(CompletionSemanticContext context,
                                                CompletionKeyword keyword) {
  double order = 8.0;
  switch (context) {
  case CompletionSemanticContext::Local:
    order = 1;
    break;
  case CompletionSemanticContext::CurrentNominal:
    order = 2;
    break;
  case CompletionSemanticContext::Super:
    order = 3;
    break;
  case CompletionSemanticContext::OutsideNominal:
    order = 4;
    break;
  case CompletionSemanticContext::CurrentModule:
    order = 5;
    break;
  case CompletionSemanticContext::OtherModule:
    order = 6.5;
    break;
  case CompletionSemanticContext::None:
    switch (keyword) {
    case CompletionKeyword::NotKeyword:
      order = 8.0;
      break;
    case CompletionKeyword::Keyword:
      order = 6.5;
      break;
    case CompletionKeyword::HighPriorityKeyword:
      order = 5.5;
      break;
    }
    break;
  }
  return (8.0 - order) / 8.0;
}

double swift_toolchain::completionScore(double matchScore, double semanticScore,
                                        const CompletionFlair &flair) {
  return (matchScore * 13 + semanticScore * 7) * flairFactor(flair);
}

swift_toolchain::CompletionBucket swift_toolchain::completionBucket(CompletionBucket group,
                                                                    bool exactMatch) {
  return exactMatch ? CompletionBucket::ExactMatch : group;
}

bool swift_toolchain::completionRanksBefore(const CompletionRank &a, const CompletionRank &b,
                                            bool filtering) {
  if (filtering) {
    const int left = filteredTier(a.bucket);
    const int right = filteredTier(b.bucket);
    if (left != right) {
      return left > right;
    }
    // SourceKit puts an exact match that is not recommended into the exact-match group. A higher
    // score there must not lift it above a recommended exact match.
    if (a.notRecommended != b.notRecommended) {
      return b.notRecommended;
    }
    // The score adds the semantic context to the match. The match alone would let a global name
    // with a slightly closer match pass a local name.
    if (a.score != b.score) {
      return a.score > b.score;
    }
  }
  if (a.bucket != b.bucket) {
    return a.bucket > b.bucket;
  }
  if (a.baseBucket != b.baseBucket) {
    return a.baseBucket > b.baseBucket;
  }
  if (a.score != b.score) {
    return a.score > b.score;
  }
  return compareInsensitive(a.name, b.name) < 0;
}
