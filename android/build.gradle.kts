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

// Force all Flutter plugins to compile against SDK 36 (required by flutter_plugin_android_lifecycle).
// file_picker 9.2.3 hardcodes compileSdk 34 in its own build.gradle, so we override it here.
// Registered via afterEvaluate so it runs AFTER each plugin's build.gradle body sets 34,
// but BEFORE AGP reads the value. The :app project is excluded — it's evaluated early by
// evaluationDependsOn(":app") above and already sets compileSdk = 36 in app/build.gradle.kts.
subprojects {
    if (name != "app") {
        afterEvaluate {
            extensions.findByType<com.android.build.gradle.BaseExtension>()
                ?.compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
