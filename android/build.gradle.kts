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

// Align every Android module on the app's compileSdk.
//
// Flutter plugin modules pin their own compileSdk and are not kept in step with
// each other: file_picker compiles against android-34 while the
// flutter_plugin_android_lifecycle it depends on declares, in its AAR metadata,
// that dependents must compile against 36 or later. That mismatch fails the build
// at :file_picker:checkDebugAarMetadata with "Update this project to use a newer
// compileSdk of at least 36".
//
// Two ordering details matter here, and both cost a build to discover:
//  1. afterEvaluate, not plugins.withId — a module sets its own compileSdk in its
//     build script, which runs *after* its plugin is applied, so configuring the
//     extension at plugin-application time is simply overwritten.
//  2. this block is registered BEFORE the evaluationDependsOn(":app") block below,
//     because afterEvaluate cannot be registered for a project that has already
//     been evaluated ("Cannot run Project.afterEvaluate(Action) when the project is
//     already evaluated").
//
// compileSdk only decides which platform APIs are visible while compiling, so this
// changes no runtime behaviour; targetSdk, which opts an app into new runtime
// behaviour, is untouched.
subprojects {
    afterEvaluate {
        when (val androidExtension = extensions.findByName("android")) {
            is com.android.build.api.dsl.LibraryExtension -> androidExtension.compileSdk = 36
            is com.android.build.api.dsl.ApplicationExtension -> androidExtension.compileSdk = 36
            else -> {
                // Not an Android module (e.g. the Flutter tool's included build).
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

