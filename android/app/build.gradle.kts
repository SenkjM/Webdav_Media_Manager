plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun envOrProp(name: String): String? =
    System.getenv(name)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }

android {
    namespace = "com.senkjm.media_manager"
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (desugaring of java.time APIs).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.senkjm.media_manager"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("internal") {
            val storePath = envOrProp("ANDROID_KEYSTORE_PATH")
            val storePassword = envOrProp("ANDROID_KEYSTORE_PASSWORD")
            val keyAlias = envOrProp("ANDROID_KEY_ALIAS")
            val keyPassword = envOrProp("ANDROID_KEY_PASSWORD")
            if (storePath != null && storePassword != null && keyAlias != null && keyPassword != null) {
                storeFile = file(storePath)
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    // 原生库压缩存放：APK 明显变小，代价是安装时要解压（安装更慢、占用更多存储）。
    // 与 `flutter build apk --split-per-abi` 配合，单包只有一份 ABI。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            val internal = signingConfigs.getByName("internal")
            signingConfig =
                if (internal.storeFile != null) {
                    internal
                } else {
                    // Local fallback only; CI must use the fixed internal keystore.
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
