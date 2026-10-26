plugins { id("com.android.application") version "9.4.1" }

android {
    namespace = "dev.androfest.clipboardprobe"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.androfest.clipboardprobe"
        minSdk = 33
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
