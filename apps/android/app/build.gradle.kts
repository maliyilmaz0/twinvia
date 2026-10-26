plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "dev.androfest.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.androfest.android"
        minSdk = 33
        targetSdk = 36
        versionCode = 11
        versionName = "0.9.0"
    }
    buildTypes {
        getByName("debug") {
            // Isolated real-device pairing tests must never replace user trust.
            if (
                providers
                    .gradleProperty("twinvia.pairingTest")
                    .orElse(providers.gradleProperty("androfest.pairingTest"))
                    .orNull == "true"
            ) {
                val suffix =
                    providers
                        .gradleProperty("twinvia.pairingTestSuffix")
                        .orElse(providers.gradleProperty("androfest.pairingTestSuffix"))
                        .orElse(".pairingtest")
                        .get()
                require(suffix.matches(Regex("\\.pairingtest[a-z0-9]*"))) {
                    "Use an isolated pairing test suffix"
                }
                applicationIdSuffix = suffix
            }
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

dependencies {
    implementation(project(":core:protocol"))
    implementation(libs.androidx.core)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.tooling.preview)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.play.scanner)
    implementation(libs.play.nearby)
    // Play Services pulls an old Fragment transitively; Activity Result requires a modern version.
    implementation(libs.androidx.fragment)
    implementation(libs.kotlinx.serialization.json)
    debugImplementation(libs.compose.tooling)
    testImplementation(libs.junit)
}
