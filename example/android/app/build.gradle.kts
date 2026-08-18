plugins {
    // Flutter 3.44 scans this block as raw text and injects legacy KGP when it
    // recognizes the literal AGP id. Gradle evaluates this escape to the same
    // plugin id while AGP 9 continues to provide built-in Kotlin support.
    id("com.android.applic\u0061tion")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "krd.pass.krdpass_auth_flutter_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "krd.pass.krdpass_auth_flutter_example"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keys so `flutter run --release` works out of the box; this is a demo.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
