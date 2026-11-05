plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
