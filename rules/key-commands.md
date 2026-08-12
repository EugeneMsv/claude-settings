# Key Commands
- `bazel build {TARGET}` - build current target
- `sh tools/checkstyle/checkstyle.sh` - Style check, before each git add
- `bazel test //src/test/java/{PATH_TO_TESTS}` - run tests for changed modules/files
- If a test target has `tags = ["java:NN"]` (e.g. `java:21`), run with `--config=java_NN`. Symptom when missing: `Unrecognized option: --add-opens` / `Could not create the Java Virtual Machine`.

## Bazel Query — Graph Navigation

```bash
# Ownership: which target owns a file?
bazel query 'attr("srcs", "MyFile.java", //src/main/java/...)'

# Tests covering a target (canonical — don't guess test paths)
bazel query 'kind(test, rdeps(//src/test/java/..., //path/to:target))'

# Impact: what depends on this target?
bazel query 'rdeps(//..., //path/to:target)' --keep_going

# Direct deps only (depth=1, avoids transitive noise)
bazel query 'deps(//path/to:target, 1)'

# All targets in a package
bazel query '//path/to/package:*'

# All java_library targets under a path
bazel query 'kind("java_library", //path/to/...)'

# Single dep chain between two targets
bazel query 'somepath(//a:target, //b:target)'

# Full dep graph — pipe to: dot -Tsvg > graph.svg
bazel query 'allpaths(//a:target, //b:target)' --output=graph

# Useful flags
--output=label_kind              # show type + label
--keep_going                     # skip broken packages in //...
--notool_deps --noimplicit_deps  # strip toolchain noise from deps()/rdeps()
```
