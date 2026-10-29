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

# PdfBox-Android's JPX (JPEG 2000) filter names the optional com.gemalto.jp2
# decoder/encoder, which is deliberately not a dependency of this app. R8 must
# not fail the minified release build on the missing classes; PDFBox only
# reaches for them when a PDF actually contains a JPX stream. (Phase 3 extracts
# text only, so this path is never exercised.)
-dontwarn com.gemalto.jp2.**

# PdfBox-Android instantiates its security handlers and the document-interchange
# handlers reflectively, so R8 must keep them by name. The AAR ships these same
# rules as consumer ProGuard rules; they are restated here so the app's own
# minify configuration pins the behaviour even if the library ever drops them.
-keep,allowobfuscation class * extends com.tom_roush.pdfbox.pdmodel.encryption.SecurityHandler {
    public <init>(...);
}
-keep,allowobfuscation class com.tom_roush.pdfbox.pdmodel.documentinterchange.** { *; }

# ColumnTextStripper overrides PDFTextStripper's protected writeString,
# writeWordSeparator, writeLineSeparator and startPage hooks. Keep the pair
# intact so optimization can never merge or strip an override PDFBox calls.
-keep class com.launcher.chronofold.mylauncher.ColumnTextStripper { *; }
-keep class com.tom_roush.pdfbox.text.PDFTextStripper { *; }
