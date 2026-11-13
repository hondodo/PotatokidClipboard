import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名：密钥与口令从 pscreen_home/cer/ 读取（相对 android/app/ 为 ../../cer/）。
// 该目录已被 cer/.gitignore 忽略，不会随仓库分发；详见 cer/README.md。
val releaseSigningStore: File = file("../../cer/potatokid-home-release.jks")
val releaseSigningPassword: String = file("../../cer/.storepass.txt").readText().trim()

android {
    namespace = "potatokid.tools.homecontroller"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "potatokid.tools.homecontroller"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 各 flavor 会覆盖 app_name；这里作为兜底，避免未配置时引用 @string/app_name 失败。
        resValue("string", "app_name", "薯仔的中控台")
        manifestPlaceholders["pkFlavor"] = "board"
    }

    // 按 ABI 分包：更新检查（check）会带 abi 参数，服务端下发对应架构的
    // APK——32 位老板子装 universal 会报"安装包损坏"，且分包把设备下载
    // 体积从 ~121MB 降到约三分之一。universal 仅作老客户端（不传 abi）
    // 的兜底产物。versionCode 由 Flutter 按 ABI 自动加偏移（见 defaultConfig 注释）。
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
        }
    }

    // `board` 沿用已上线包名 potatokid.tools.homecontroller（服务端 kindOfApp()
    // 按包名识别 home，且该包当前就以 HOME 方式作为桌面运行）；
    // phone / parent 用后缀区分，可同机安装共存。
    flavorDimensions += "product"

    productFlavors {
        create("board") {
            dimension = "product"
            applicationId = "potatokid.tools.homecontroller"
            resValue("string", "app_name", "薯仔的中控台")
            manifestPlaceholders["pkFlavor"] = "board"
        }
        create("phone") {
            dimension = "product"
            applicationId = "potatokid.tools.homecontroller.phone"
            versionNameSuffix = "-phone"
            resValue("string", "app_name", "薯仔手机端")
            manifestPlaceholders["pkFlavor"] = "phone"
        }
        create("parent") {
            dimension = "product"
            applicationId = "potatokid.tools.homecontroller.parent"
            versionNameSuffix = "-parent"
            resValue("string", "app_name", "薯仔家长端")
            manifestPlaceholders["pkFlavor"] = "parent"
        }
    }

    // 正式 release 签名配置：从 pscreen_home/cer/ 读取（见文件顶部 val 定义）。
    signingConfigs {
        create("release") {
            storeFile = releaseSigningStore
            storePassword = releaseSigningPassword
            keyAlias = "potatokid-home"
            keyPassword = releaseSigningPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // SDK 集成要求：多个依赖都带 libc++_shared.so，打包时保留首个，避免重复冲突。
    packaging {
        jniLibs {
            pickFirsts += listOf(
                "lib/x86/libc++_shared.so",
                "lib/x86_64/libc++_shared.so",
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/arm64-v8a/libc++_shared.so",
            )
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
