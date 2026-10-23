import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload signing (Play Store). The key material lives OUTSIDE version control
// in android/key.properties + android/upload-keystore.jks (both git-ignored),
// and every value below is read from that file — no credential is ever
// written into this build script. When the file is absent (CI, fresh clone)
// the release build falls back to debug signing so ordinary builds keep
// working; a Play upload of a debug-signed bundle is rejected loudly.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKeystore = keystorePropertiesFile.exists()
if (hasUploadKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.shuro.shuro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.shuro.shuro"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // One stable debug key, committed with the app. Without it the
        // fallback used Gradle's per-machine debug keystore, which on CI is
        // regenerated EVERY run — each debug-signed release then had a new
        // signature and no release could install over the previous one
        // ("App not installed"). A debug key guards nothing; committing it
        // is standard practice and makes every debug-signed release a real
        // upgrade path. Real signing still wins whenever the upload keystore
        // secrets are configured.
        create("shuroDebug") {
            storeFile = rootProject.file("app/shuro-debug.keystore")
            storePassword = "android"
            keyAlias = "shuro-debug"
            keyPassword = "android"
        }
        if (hasUploadKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("shuroDebug")
            }
            // Shrinking stays OFF on release. shared_preferences_android talks
            // to its Kotlin through package:jni reflective lookups that R8
            // cannot see, and a shrunk build dropped the legacy getAll —
            // every release install then failed at connect with
            // NoSuchMethodError while debug builds worked. If shrinking is
            // ever re-enabled, proguard-rules.pro must keep the whole
            // sharedpreferences package first.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
