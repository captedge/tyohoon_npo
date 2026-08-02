allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker's own module (and any other plugin module) may still ship
// compiled against an older compileSdk than this app now needs (see
// app/build.gradle.kts — bumped to 36 because of file_picker's transitive
// dependency flutter_plugin_android_lifecycle). Force every *plugin*
// module to build against the same compileSdk so their AAR metadata
// checks don't fail too (confirmed necessary 2026-08-02: the app-level
// bump alone was not enough — file_picker's own module still failed its
// own checkReleaseAarMetadata task until this was added).
// Skip ":app" itself: the evaluationDependsOn(":app") block above already
// forces the app module to fully evaluate early, so by the time this runs
// ":app" is already evaluated and calling afterEvaluate on it throws
// "Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated." app/build.gradle.kts already sets its own compileSdk anyway.
subprojects {
    if (project.path != ":app") {
        afterEvaluate {
            extensions.findByType<com.android.build.gradle.BaseExtension>()?.let { android ->
                android.compileSdkVersion(36)
            }
        }
    }
}

// Workaround for a known upstream bug in the file_picker Android plugin
// (this app uses file_picker 8.3.7 — see pubspec.lock — for Passage Plan
// CSV import; see https://github.com/miguelpruivo/flutter_file_picker/issues/1973
// and .../issues/1952, still reproducible on 11.0.2 as of 2026-07-18 in the
// sibling ShipsTime project, docs/flutter-android-env-notes.md).
//
// file_picker's own android/build.gradle applies com.android.library but
// not the Kotlin Android plugin, even though all its source is Kotlin.
// Without that plugin, Gradle never compiles its .kt files, so the
// generated GeneratedPluginRegistrant.java fails with "cannot find symbol
// FilePickerPlugin" — not a mistake in this project's own code.
//
// This force-applies the Kotlin Android plugin (and pins the same JVM
// target 17 used in app/build.gradle.kts) to any Android-library
// subproject that's missing it. Applied preemptively, before actually
// hitting the build failure, based on the ShipsTime project's confirmed
// experience with the same plugin. Safe to remove once file_picker ships a
// real fix and this project upgrades past the broken version.
subprojects {
    plugins.whenPluginAdded {
        if (this is com.android.build.gradle.LibraryPlugin) {
            if (!project.plugins.hasPlugin("org.jetbrains.kotlin.android")) {
                project.plugins.apply("org.jetbrains.kotlin.android")
            }
            project.extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java)
                ?.compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
