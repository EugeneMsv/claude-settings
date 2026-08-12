---
paths:
  - "**/*.java"
  - "**/*.kt"
  - "**/*.kts"
---

# All Java related guides

## Project Conventions
- No `@Nullable` annotations — not typically used

## jdtls / Diagnostics
- jdtls has no Bazel support: unresolved-import and "missing type" diagnostics on Java files are EXPECTED FALSE POSITIVES — ignore them, don't report them, don't "fix" them.
- Source of truth for whether Java compiles is `bazel build`, never jdtls diagnostics.

## codestyle guide
1. `final` everywhere is preferred
2. Prefer records for data carriers
3. Use single early return with `||` for multiple skip conditions
Example: `if (condition1 || condition2 || condition3) return;`
4. Prefer `Optional.ofNullable(x).map(X::foo).map(Foo::bar).orElse(null)` over multi-step null guards
5. Never use a one-element array/holder (`final T[] x = {null}`) to mutate state from a lambda or anonymous class — use a named local class with a field, or a plain `for` loop
6. Prefer a plain `for` loop over `forEach`/stream-lambda when the body reads or mutates outer local state
7. Prefer `"template".formatted(args)` over `String.format("template", args)`

## Testing Patterns

### JMockit (legacy tests):
1. **Never mix `@Mocked` parameter with inline `MockUp`**: Declaring `new MockUp<X>()` inside a test that has `@Mocked Y` as a parameter resets JMockit's invocation recording mid-test — already-fired calls on Y become "unexpected invocation". Fix: declare the `@Mocked` mock programmatically *after* all `MockUp` blocks using `new mockit.Expectations(instance) {{}}`, then use `Verifications` against that instance.
2. **`times=0` with all-`any` wildcards matches by arity, not by method identity**: If two calls have the same number of vararg args, a wildcard `times=0` will also match the sibling call. Use exact args for `times=0` assertions.

### Mockito + JUnit 5:
#### Test Structure:
1. Use `@ExtendWith(MockitoExtension.class)` at class level
2. Use `@Mock` annotations on method parameters for test-specific mocks
3. Use `@InjectMocks` for the class under test as a field
4. Test naming and structure: see coding.md (Given-When-Then, `test_methodName_condition_expectedResult`)

#### Mockito Best Practices:
1. **Avoid lenient mode**: Fix unnecessary stubbing issues by removing unused stubs, don't use `lenient()`
2. **Only stub what's called**: Stub only methods actually invoked during test execution
3. **Prefer @Mock parameters**: Use `@Mock` on method parameters even for simple objects that don't need stubbing. Keeps test
   structure consistent and avoids mixing `@Mock` with `mock()` calls.

#### Test Data:
1. Use literal values directly in tests, not static constants
2. Use `Month.JANUARY` enum instead of numeric month values
3. Example: `LocalDateTime.of(2024, Month.JANUARY, 1, 0, 0)`
4. Avoid depending on a production default in a test when the value can be mocked/set — pin it explicitly so a default change can't silently alter the test.

#### Error Validation:
1. Use `.hasFieldOrPropertyWithValue()` for detailed error assertions


#### Success Validation:
1. **Don't use assertThatCode**: For tests expecting no exception, call the method directly. The test will fail if an exception is thrown.
    - ❌ Bad: `assertThatCode(() -> validator.validate()).doesNotThrowAnyException()`
    - ✅ Good: `validator.validate();`
