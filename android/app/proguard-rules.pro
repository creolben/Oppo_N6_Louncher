# The Flutter Gradle plugin contributes the keep rules for the embedding and the
# engine's JNI entry points, so nothing here needs to restate them.

# MainActivity is named in AndroidManifest.xml, which R8 reads, so it is kept
# automatically. Its method-channel handlers are reached through lambdas from
# Kotlin rather than reflection, so they need no rules either.

# Kotlin's intrinsics throw with parameter names embedded in the message. Keeping
# the metadata off makes those messages less readable but does not break them.
-dontwarn kotlin.Metadata

# Play Core is referenced by Flutter's deferred-components support. This launcher
# does not use deferred components, so the classes are absent at compile time and
# the missing-class warnings are expected.
-dontwarn com.google.android.play.core.**
