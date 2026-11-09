import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名口令从本地 .storepass.txt 读取，避免在脚本中硬编码明文口令。
val releaseSigningStore: File = file("potatokid-release.jks")
val releaseSigningPassword: String = file(".storepass.txt").readText().trim()

android {
    namespace = "screen.potatokid.tools"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            storeFile = releaseSigningStore
            storePassword = releaseSigningPassword
            keyAlias = "potatokid"
            keyPassword = releaseSigningPassword
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "screen.potatokid.tools"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 各 flavor 会覆盖 app_name；这里作为兜底，避免未配置时引用 @string/app_name 失败。
        resValue("string", "app_name", "薯仔看电视")
        manifestPlaceholders["pkFlavor"] = "tv"
    }

    // 按 ABI 分包：更新检查（check）会带 abi 参数，服务端下发对应架构的
    // APK——32 位老板子装 universal 会报"安装包损坏"，且分包把设备下载
    // 体积从 ~121MB 降到约三分之一。universal 仅作老客户端（不传 abi）
    // 的兜底产物。versionCode 由 Flutter 按 ABI 自动加偏移。
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
        }
    }

    // `tv` 沿用已上线包名 screen.potatokid.tools（服务端 kindOfApp() 按包名识别电视端），
    // 其它 flavor 用后缀区分，可同机安装共存。
    flavorDimensions += "product"

    productFlavors {
        create("tv") {
            dimension = "product"
            applicationId = "screen.potatokid.tools"
            resValue("string", "app_name", "薯仔看电视")
            manifestPlaceholders["pkFlavor"] = "tv"
        }
        create("phone") {
            dimension = "product"
            applicationId = "screen.potatokid.tools.phone"
            versionNameSuffix = "-phone"
            resValue("string", "app_name", "薯仔看电视")
            manifestPlaceholders["pkFlavor"] = "phone"
        }
        create("board") {
            dimension = "product"
            applicationId = "screen.potatokid.tools.board"
            versionNameSuffix = "-board"
            resValue("string", "app_name", "薯仔电视桌面")
            manifestPlaceholders["pkFlavor"] = "board"
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

flutter {
    source = "../.."
}