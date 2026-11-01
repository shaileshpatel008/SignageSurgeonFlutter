import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — read from android/key.properties (gitignored, never
// committed). Falls back to the debug key below when that file doesn't
// exist, so `flutter build apk --release` still works out of the box for
// anyone who hasn't set up a keystore yet; just never ship a Play Store
// build signed that way. Copy android/key.properties.sample to get started.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.signagesurgeon.app"
    // Google Play requires new apps/updates to target Android 16 (API 36)
    // as of Aug 31, 2026 — targetSdk 34 would be rejected at upload today.
    // Hardcoded rather than left on flutter.compileSdkVersion so this
    // doesn't silently regress if an older Flutter SDK is used to build.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Final — matches the Android app already registered in Firebase
        // (google-services.json), so this can't change without
        // re-registering a new Firebase Android app and swapping configs.
        applicationId = "com.signagesurgeon.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // No key.properties yet — sign with the debug key so
                // `flutter run --release` / `flutter build apk --release`
                // still work locally. Never ship a Play Store build signed
                // this way.
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
