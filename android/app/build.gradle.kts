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

// `flutter build apk --split-per-abi` 传入 -Psplit-per-abi=true，会给每个
// variant 打开 splits.abi。AGP 只要任一 variant 还留着 ndk.abiFilters 就失败，
// 包括正在编 prod 时一并配置的 sandbox。
val splitPerAbi =
    findProperty("split-per-abi")?.toString()?.toBoolean() == true

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


    // Optional libsodium for openlist_crypt secretbox (arm64-v8a only in this
    // experiment). Other ABIs simply omit the .so and stay on the Dart path.
    // Does not set abiFilters — sandbox abiFilters / split-per-abi rules unchanged.
    sourceSets {
        getByName("main") {
            jniLibs.srcDir("../../packages/openlist_crypt/native/android")
        }
    }

    defaultConfig {
        applicationId = "com.senkjm.media_manager"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "Webdav Media Manager"
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
        create("sandbox") {
            val storePath = envOrProp("ANDROID_SANDBOX_KEYSTORE_PATH")
            val storePassword = envOrProp("ANDROID_SANDBOX_KEYSTORE_PASSWORD")
            val keyAlias = envOrProp("ANDROID_SANDBOX_KEY_ALIAS")
            val keyPassword = envOrProp("ANDROID_SANDBOX_KEY_PASSWORD")
            if (storePath != null && storePassword != null && keyAlias != null && keyPassword != null) {
                storeFile = file(storePath)
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    // flavor 只决定「装成哪个包、叫什么名字」，不碰 namespace 与 Dart 代码：
    // prod、dev 与 test 的 applicationId 不同，所以能并存在同一台手机上，各自持有
    // 独立的数据库 / 偏好 / 安全存储目录。
    // 注意：一旦存在 product flavor，AGP 就不再生成不带 flavor 的
    // assembleRelease 之类任务，所有构建都必须显式带 --flavor。
    // abiFilters 只在非 split-per-abi 时写在 sandbox 上。prod / dev 不设，
    // 仍由各自的构建命令决定 ABI。分包构建不能带这份过滤，否则 prod 的
    // --split-per-abi 会在配置 sandbox variant 时失败。
    // flavor 不能叫 test：AGP 禁止 ProductFlavor 名字以 test 开头。
    // 签名按 flavor 写死（buildType release 不再设 signingConfig，否则会盖过 flavor）：
    // - prod / dev：有 internal keystore（CI secrets 或 android/key.properties）就用它，
    //   本地没有时回落 debug，仅够自测。正式 / 预发布 CI 必须带 internal。
    // - sandbox：有 sandbox 专用 keystore（ANDROID_SANDBOX_* secrets / key.properties）就用它，
    //   本地没有时回落 debug。Testbuild 解码固定测试 keystore，跨次可覆盖安装。
    // debug buildType 仍用 AGP 默认的 debug 签名。
    val internalSigning = signingConfigs.getByName("internal")
    val releaseSigning =
        if (internalSigning.storeFile != null) internalSigning else signingConfigs.getByName("debug")
    val sandboxKeySigning = signingConfigs.getByName("sandbox")
    val sandboxSigning =
        if (sandboxKeySigning.storeFile != null) sandboxKeySigning else signingConfigs.getByName("debug")

    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            signingConfig = releaseSigning
        }
        create("dev") {
            dimension = "env"
            signingConfig = releaseSigning
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appName"] = "Webdav Media Manager Dev"
        }
        create("sandbox") {
            dimension = "env"
            applicationIdSuffix = ".test"
            versionNameSuffix = "-test"
            manifestPlaceholders["appName"] = "Webdav Media Manager Test"
            signingConfig = sandboxSigning
            if (!splitPerAbi) {
                ndk {
                    abiFilters += "arm64-v8a"
                }
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

    // release 的签名由各 flavor 决定（见 productFlavors 上方注释），这里不设。
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
