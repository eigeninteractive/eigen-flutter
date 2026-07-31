group = "com.eigeninteractive.eigen_flutter"
version = "1.0-SNAPSHOT"

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.eigeninteractive.eigen_flutter"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    // FID-based registration landed after FlutterFire's currently pinned BoM.
    // Exporting the platform constraint lets Gradle select this version for
    // FlutterFire too. Remove the pin once firebase_core carries it or newer.
    api(platform("com.google.firebase:firebase-bom:34.16.0"))
    api("com.google.firebase:firebase-messaging")
}
