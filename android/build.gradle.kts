import com.android.build.api.variant.LibraryAndroidComponentsExtension

plugins {
    // Version is provided by settings.gradle.kts (AGP 9.0.1).
    // Expose the shared AGP API to the root build script.
    id("com.android.application") apply false
}

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
// Fix the Android DSL before AGP creates its variants and compile tasks.
// Flutter's Kotlin integration targets JVM 17; tflite_flutter 0.12.1
// declares Java 11. A task-only afterEvaluate override was insufficient.
// Register this callback before evaluationDependsOn(":app") can evaluate
// any plugin projects. Scope strictly to tflite_flutter.
subprojects {
    if (name == "tflite_flutter") {
        val tfliteProject = this
        pluginManager.withPlugin("com.android.library") {
            tfliteProject.extensions
                .getByType(LibraryAndroidComponentsExtension::class.java)
                .finalizeDsl { android ->
                    android.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                    android.compileOptions.targetCompatibility = JavaVersion.VERSION_17
                    tfliteProject.logger.lifecycle(
                        "[Kyeobom] tflite_flutter finalized Java target: " +
                            android.compileOptions.targetCompatibility
                    )
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
