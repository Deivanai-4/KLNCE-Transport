plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.klnce.transport"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    defaultConfig {
        applicationId = "com.klnce.transport"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ── Release Signing ─────────────────────────────────────────────────────
    // To build a signed release APK / AAB:
    //   1. Generate a keystore: keytool -genkey -v -keystore klnce-release.jks
    //      -alias klnce -keyalg RSA -keysize 2048 -validity 10000
    //   2. Create android/key.properties with:
    //         storePassword=<password>
    //         keyPassword=<password>
    //         keyAlias=klnce
    //         storeFile=../klnce-release.jks
    //   3. The block below reads key.properties automatically.
    //   key.properties and klnce-release.jks are in .gitignore — never commit them.
    signingConfigs {
        // Debug config is used automatically for debug builds — no changes needed.
        // Release config: reads from key.properties if it exists; falls back to debug.
        create("release") {
            val keyPropsFile = rootProject.file("key.properties")
            if (keyPropsFile.exists()) {
                val keyProps = java.util.Properties()
                keyProps.load(java.io.FileInputStream(keyPropsFile))
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
            } else {
                // Fallback to debug signing when key.properties is not present
                // (CI/CD or first-time build). Do NOT ship this to users.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false   // Enable and configure ProGuard when ready
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
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
