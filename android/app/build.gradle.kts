import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (local, gitignored) or
// ANDROID_KEYSTORE_PATH / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS (CI).
// With neither present, release falls back to the debug key so PR builds and
// fresh clones still build.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
fun signingValue(prop: String, env: String): String? =
    keystoreProperties.getProperty(prop) ?: System.getenv(env)
val releaseStoreFile: String? = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val hasReleaseSigning = releaseStoreFile != null && file(releaseStoreFile).exists()

android {
    namespace = "com.launcher.chronofold.mylauncher"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.launcher.chronofold.mylauncher"
        minSdk = 26
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseSigning) "release" else "debug")

            // AGP 9 already turns both of these on for release, so this block
            // changes nothing today — it pins the behaviour so an AGP default
            // change or a stray `false` cannot silently re-add 5.6MB of dex.
            // Measured here: off -> classes.dex 6,188,764 B and 87 res entries;
            // on -> 545,000 B and 8 res entries.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Native debug symbols are deliberately NOT retained. Keeping them made the
    // release APK 508MB, because the unstripped libflutter.so is ~165MB per ABI.
    // Symbolicate release crashes with `--split-debug-info` output instead.
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // On-device PDF text-layer extraction (Phase 3). Pinned to 2.0.27.0 — the
    // newest release in Maven Central (metadata lastUpdated 2023-01-02) — so a
    // later publish cannot change the text extractor under the launcher.
    // https://repo1.maven.org/maven2/com/tom-roush/pdfbox-android/maven-metadata.xml
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
}
