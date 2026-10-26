pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "TwinviaClipboardProbe"

apply(from = file("../../apps/android/gradle/dependency-security.settings.gradle.kts"))
