allprojects {
    repositories {
        google()
        mavenCentral()
    }

        configurations.all {
        resolutionStrategy {
            // Force LiteRT to a newer version than what tflite_flutter is pulling (1.4.0)
            // Adjust if Gradle says the version doesn't exist in your repos.
            force("com.google.ai.edge.litert:litert:1.4.1")
            force("com.google.ai.edge.litert:litert-api:1.4.1")
            force("com.google.ai.edge.litert:litert-gpu:1.4.1")
            force("com.google.ai.edge.litert:litert-gpu-api:1.4.1")

            // Defensive: if anything pulls classic TF Lite as well, keep it modern.
            force("org.tensorflow:tensorflow-lite:2.14.0")
            force("org.tensorflow:tensorflow-lite-api:2.14.0")
        }
    }
    
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
plugins {
    // Google Services plugin for parsing google-services.json
    // Version is managed in settings.gradle.kts (FlutterFire injected)
    // to avoid classpath conflicts. Do not redeclare here.
}
