group = "krd.pass.krdpass_auth"
version = "1.6.0"

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    // AGP 9+ ships Kotlin built-in, so no separate org.jetbrains.kotlin.android id here.
    id("com.android.library")
}

android {
    namespace = "krd.pass.auth"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // Must be >= the core Android SDK's minimum.
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    // Strict: this is a security SDK, so a consumer's unrelated dependency must not be able
    // to quietly upgrade or downgrade the core out from under it.
    implementation("krd.pass:krdpass-auth:1.6.0!!")
    testImplementation("junit:junit:4.13.2")
}
