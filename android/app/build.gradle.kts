import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 固定的发布签名：保证每次打包的 APK 都能覆盖安装（不丢失设置与指纹解锁）。
// 云端打包时从 GitHub Secrets 注入的环境变量读取；本地打包读取 android/key.properties。
// 两者都没有时退回 debug 签名。
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
    System.getenv("PV_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }?.let {
        setProperty("storeFile", it)
        setProperty("storePassword", System.getenv("PV_KEYSTORE_PASSWORD") ?: "")
        setProperty("keyAlias", System.getenv("PV_KEY_ALIAS") ?: "passvault")
        setProperty("keyPassword", System.getenv("PV_KEYSTORE_PASSWORD") ?: "")
    }
}

android {
    namespace = "com.xichugeek.passvault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.xichugeek.passvault"
        // 自动填充需要 Android 8.0（API 26）
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keyProps.getProperty("storeFile") != null) {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyProps.getProperty("storeFile") != null)
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // 原生 Argon2 / AES-KDF（解锁加速）
    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.autofill:autofill:1.1.0")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
}

flutter {
    source = "../.."
}
