plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.typhoon_ship_tracker"
    // file_picker's transitive dependency flutter_plugin_android_lifecycle
    // requires compileSdk 36+ (confirmed 2026-08-02: ":file_picker:checkReleaseAarMetadata"
    // FAILURE — "file_picker is currently compiled against android-34" —
    // when built at Flutter's default compileSdk). See also the matching
    // subprojects block in ../build.gradle.kts, which forces every *plugin*
    // module (not just this app) to the same compileSdk so their own
    // AAR metadata checks don't fail either.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    // ndkVersion intentionally omitted: none of this app's dependencies
    // (file_picker/shared_preferences/path_provider/xml/cupertino_icons)
    // need native (NDK) code, and the NDK's own download is a heavy ~750MB
    // (docs/flutter-android-env-notes.md, carried over from the ShipsTime
    // project which confirmed this on the same machine/connection).

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.typhoon_ship_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
