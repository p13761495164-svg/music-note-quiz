plugins {
    id("com.android.application")
}

android {
    namespace = "com.benhuang.musicnotequiz"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.benhuang.musicnotequiz"
        minSdk = 23
        targetSdk = 36
        versionCode = 3
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
