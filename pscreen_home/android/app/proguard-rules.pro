# shared_preferences_android 2.5.x 使用 package:jni（jnigen 生成代码）在运行时按类名/方法签名
# 反射调用 Kotlin 代码。release 包默认开启 R8，会重命名或删除这些运行时才用到的类：
#   - kotlin.coroutines.Continuation 被改名 -> NoSuchMethodError: getAll(...)
#   - kotlin.Result / Result$Failure 被裁掉 -> ClassNotFoundException
# 结果是读取/写入本地配置全部抛 PlatformException，SettingsStore 静默回落 .env（localhost）。
# 以下规则保留 JNI 反射所需的插件类与 Kotlin 运行时类型。
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.Result* { *; }
-keep class kotlin.Unit { *; }
