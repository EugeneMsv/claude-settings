# Coding Instructions

## Generic Coding Style Guide (All languages):
1. Clean, readable, modular code; meaningful names; comment only non-obvious WHY (workarounds, invariants, edge-case constraints — not what the code does).
2. No unnecessary complexity; no hardcoded values (use constants/config); follow SOLID for multi-class structures; follow project contribution guidelines.
3. Tests follow Given-When-Then.
4. During iteration, run the affected single test and verify it passes. (Full suite at pre-commit gate; see workflows.md.)
5. Prefer fluent/chained calls for transformations and assertions. NOT when: (a) lambda reads/mutates outer local state, (b) chain exceeds ~4 links, (c) side effect is hidden — use plain statements instead.
6. Add imports in the SAME edit as the code that uses them, or in a LATER edit — never in a separate edit before the code exists
7. Prefer parametrized tests over single case tests
8. Extract to a named method when: 5+ lines, 2+ nesting levels, or reused. Do not extract single-expression calculations.
9. Avoid generic variable names (`data`, `result`, `obj`, `item`) in production/service code — use type-qualified names (e.g., `subscriptionData`, `paymentResult`); test-local variables are exempt
10. When writing a test, define its test data/fixtures (builders, helper factories) FIRST, then write the test body against them — never reference a fixture/helper that does not exist yet
11. Test method naming: `test_methodName_condition_expectedResult`
12. Before writing any `file:line` citation into a doc/explanation (not just when editing), grep/verify the exact line — don't rely on remembered file structure for multi-hop call chains.


## Script/Tool Creation:
For "smart"/"robust"/"production"/"reusable" scripts, or any script run more than once:
- Include health checks, status monitoring
- Add color-coded output for clarity
- Implement safety confirmations for destructive actions
- Provide comprehensive help/usage information
- Include both simple and advanced usage modes
- Prefer feature-rich over minimal implementations
For throwaway one-offs, follow the global keep-it-simple rule.
