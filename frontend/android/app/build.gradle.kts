import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeyProperties = keystorePropertiesFile.exists()
if (hasKeyProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.klnce.transport"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    defaultConfig {
        applicationId = "com.klnce.transport"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ── Release Signing ─────────────────────────────────────────────────────
    // If android/key.properties exists, uses the custom release keystore.
    // Otherwise, safely falls back to debug signing for local testing.
    signingConfigs {
        create("release") {
            if (hasKeyProperties) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = if (hasKeyProperties) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
    }
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:35.2.0"))

    // Firebase Analytics
    implementation("com.google.firebase:firebase-analytics")

    // WorkManager — for background scheduled SMS jobs (Stage 8)
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // Core KTX and notifications (for notification builder in SmsScheduleWorker)
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
