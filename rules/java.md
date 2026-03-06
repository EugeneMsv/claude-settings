---
paths:
  - "**/*.java"
  - "**/*.kt"
  - "**/*.kts"
---

# All Java related guides

## codestyle guide
1. `final` and `var` keywords everywhere are preferred
2. Prefer records for data carriers
3. Use single early return with `||` for multiple skip conditions
Example: `if (condition1 || condition2 || condition3) return;`
4. Prefer `Optional.ofNullable(x).map(X::foo).map(Foo::bar).orElse(null)` over multi-step null guards

## Testing Patterns 

### Mockito + JUnit 5:
#### Test Structure:
1. Use `@ExtendWith(MockitoExtension.class)` at class level
2. Use `@Mock` annotations on method parameters for test-specific mocks
3. Use `@InjectMocks` for the class under test as a field
4. Test naming: `test_methodName_condition_expectedResult`
5. Structure: Given-When-Then with clear comment sections

#### Mockito Best Practices:
1. **Avoid lenient mode**: Fix unnecessary stubbing issues by removing unused stubs, don't use `lenient()`
2. **Only stub what's called**: Stub only methods actually invoked during test execution
3. **Prefer @Mock parameters**: Use `@Mock` on method parameters even for simple objects that don't need stubbing. Keeps test
   structure consistent and avoids mixing `@Mock` with `mock()` calls.

#### Test Data:
1. Use literal values directly in tests, not static constants
2. Use `Month.JANUARY` enum instead of numeric month values
3. Example: `LocalDateTime.of(2024, Month.JANUARY, 1, 0, 0)`

#### Error Validation:
1. Use `.hasFieldOrPropertyWithValue()` for detailed error assertions


#### Success Validation:
1. **Don't use assertThatCode**: For tests expecting no exception, call the method directly. The test will fail if an exception is thrown.
    - ❌ Bad: `assertThatCode(() -> validator.validate()).doesNotThrowAnyException()`
    - ✅ Good: `validator.validate();`
