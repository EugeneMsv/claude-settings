---
paths:
  - "**/*.java"
  - "**/*.kt"
  - "**/*.kts"
---

# All Kotlin related guides

## Testing Patterns 

### MockK + JUnit 5 (for Kotlin):
#### Test Structure:
1. Use `@ExtendWith(MockKExtension::class)` at class level
2. Use `@MockK` annotations for mocked dependencies
3. Use `@InjectMockKs` for the class under test
4. Test naming and structure: see coding.md (Given-When-Then, `test_methodName_condition_expectedResult`)
