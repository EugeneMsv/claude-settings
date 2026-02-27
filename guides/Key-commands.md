# Key Commands
- `./gradlew spotlessApply` - Format code (ALWAYS run before git add)
- `./gradlew clean spotlessApply test --tests "com.your.package.YourTestClass"` - Run single test class
- `./gradlew test --tests "com.your.package.YourTestClass.test_method"` - Run single test method
- `./gradlew clean spotlessApply test` - Full verification (clean, format, test all)
