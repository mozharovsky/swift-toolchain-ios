#include "BundledPluginPolicy.h"
#include "SwiftToolchainPluginPolicy.h"
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <unistd.h>

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#endif

namespace {

/// CTest receives every failed path contract before the owned fixtures are removed.
int check(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    return 1;
  }
  return 0;
}

/// Creates a regular file whose contents identify which canonical fixture a caller opened.
bool writeFixture(const std::filesystem::path &path, const char *contents) {
  std::error_code error;
  std::filesystem::create_directories(path.parent_path(), error);
  if (error) {
    return false;
  }
  std::ofstream file(path);
  file << contents;
  return file.good();
}

/// Exercises the same main-bundle entry point used across the compiler and macro frameworks.
int checkMainBundle(const std::filesystem::path &outside, const std::string &fixtureName) {
#if defined(__APPLE__)
  const auto bundle = CFBundleGetMainBundle();
  if (bundle == nullptr) {
    return check(false, "The test executable must have a main bundle.");
  }
  const auto url = CFBundleCopyPrivateFrameworksURL(bundle);
  if (url == nullptr) {
    return check(false, "The test bundle must describe its private frameworks directory.");
  }
  UInt8 directory[PATH_MAX];
  const bool represented =
      CFURLGetFileSystemRepresentation(url, true, directory, sizeof(directory));
  CFRelease(url);
  if (!represented) {
    return check(false, "The test frameworks directory must have a filesystem path.");
  }
  const auto framework = std::filesystem::path(reinterpret_cast<const char *>(directory)) /
                         (fixtureName + ".framework");
  const auto executable = framework / fixtureName;
  if (!writeFixture(executable, "bundled")) {
    return check(false, "Create the main-bundle plugin fixture.");
  }
  int failures = 0;
  char *copied = swift_toolchain_copy_bundled_plugin_path(executable.c_str());
  failures += check(copied != nullptr && copied == std::filesystem::canonical(executable).string(),
                    "The public policy entry point must return its owned canonical path.");
  std::free(copied);
  copied = swift_toolchain_copy_bundled_plugin_path(outside.c_str());
  failures +=
      check(copied == nullptr, "The public policy entry point must reject an external file.");
  std::free(copied);
  copied = swift_toolchain_copy_bundled_plugin_path(nullptr);
  failures += check(copied == nullptr, "A missing plugin path must fail without borrowed storage.");
  std::free(copied);
  std::error_code error;
  std::filesystem::remove_all(framework, error);
  failures += check(!error, "Remove the owned main-bundle fixture.");
  return failures;
#else
  (void)fixtureName;
  char *copied = swift_toolchain_copy_bundled_plugin_path(outside.c_str());
  const int failures =
      check(copied == nullptr, "A platform without app bundles must reject plugins.");
  std::free(copied);
  return failures;
#endif
}

} // namespace

/// Runs isolated path and ownership checks without loading or executing a plugin.
int main() {
  char temporary[] = "/tmp/swift-toolchain-profile.XXXXXX";
  const auto created = mkdtemp(temporary);
  if (created == nullptr) {
    return check(false, "Create the owned plugin-policy test directory.");
  }
  const std::filesystem::path root(created);
  const auto frameworks = root / "Frameworks";
  const auto valid = frameworks / "Allowed.framework/Allowed";
  const auto outside = root / "Frameworks-other/Outside.framework/Outside";
  const auto wrongName = frameworks / "Wrong.framework/Other";
  const auto nested = frameworks / "Nested.framework/Subdirectory/Nested";
  int failures = 0;
  const bool prepared = writeFixture(valid, "inside") && writeFixture(outside, "outside") &&
                        writeFixture(wrongName, "wrong") && writeFixture(nested, "nested");
  failures += check(prepared, "Create the framework layout fixtures.");
  if (prepared) {
    const auto canonical = std::filesystem::canonical(valid).string();
    failures += check(swift_toolchain::bundledFrameworkExecutablePath(frameworks.c_str(),
                                                                      valid.c_str()) == canonical,
                      "A direct framework executable must resolve to its canonical path.");
    for (const auto &invalid :
         {outside, wrongName, nested, valid.parent_path(), root / "Missing"}) {
      failures +=
          check(swift_toolchain::bundledFrameworkExecutablePath(frameworks.c_str(), invalid.c_str())
                    .empty(),
                "External, malformed, missing, and directory paths must be rejected.");
    }
    failures +=
        check(swift_toolchain::bundledFrameworkExecutablePath(nullptr, valid.c_str()).empty(),
              "An absent framework root must be rejected.");
    failures +=
        check(swift_toolchain::bundledFrameworkExecutablePath(frameworks.c_str(), nullptr).empty(),
              "An absent plugin path must be rejected.");
    const auto alias = root / "PluginAlias";
    std::filesystem::create_symlink(valid, alias);
    const auto resolved =
        swift_toolchain::bundledFrameworkExecutablePath(frameworks.c_str(), alias.c_str());
    failures += check(resolved == canonical, "An alias must return the canonical bundled path.");
    std::filesystem::remove(alias);
    std::filesystem::create_symlink(outside, alias);
    failures += check(
        swift_toolchain::bundledFrameworkExecutablePath(frameworks.c_str(), alias.c_str()).empty(),
        "An alias redirected outside the bundle must be rejected.");
    std::ifstream file(resolved);
    std::string contents;
    file >> contents;
    failures +=
        check(contents == "inside", "A returned path must remain safe after alias mutation.");
    failures += checkMainBundle(outside, root.filename().string());
  }
  std::error_code error;
  std::filesystem::remove_all(root, error);
  failures += check(!error, "Remove the owned plugin-policy test directory.");
  return failures == 0 ? 0 : 1;
}
