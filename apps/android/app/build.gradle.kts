plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "dev.androfest.android"
    compileSdk = 37
    defaultConfig {
        applicationId = "dev.androfest.android"
        minSdk = 33
        targetSdk = 36
        versionCode = 11
        versionName = "0.9.0"
        buildConfigField(
            "String",
            "UPDATE_PUBLIC_KEY",
            "\"LTBw49qAUZkD4makhIWN5ITZ4uiXzRBc9kDDAb7RHnA=\"",
        )
    }
    val distributionStore = System.getenv("TWINVIA_KEYSTORE_PATH")
    val distributionSigning =
        if (!distributionStore.isNullOrEmpty())
            signingConfigs.create("distribution") {
                storeFile = file(distributionStore)
                storePassword =
                    System.getenv("TWINVIA_KEYSTORE_PASSWORD") ?: error("Missing signing password")
                keyAlias = "twinvia"
                keyPassword = storePassword
            }
        else null
    buildTypes {
        getByName("debug") {
            if (distributionSigning != null) signingConfig = distributionSigning
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
