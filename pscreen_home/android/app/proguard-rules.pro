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

# nim_core_v2（网易云信 IM）引用了一批可选依赖的可选类，R8 在 release 下会因找不到
# 这些类而直接判定构建失败（Missing class ...）：
#   - net.zetetic.database.sqlcipher.*  加密版 SQLite（商业版才有）
#   - org.conscrypt.* / org.openjsse.*    可选的 JSSE provider
#   - org.bouncycastle.jsse.*             可选的 BouncyCastle provider
#   - com.netease.nimlib.aop/apt.*        注解处理器生成的可选注解
# 这些运行时不会被调用（未启用加密 DB / 未指定 TLS provider），仅需压制警告。
-dontwarn com.netease.nimlib.aop.annotation.CostTime
-dontwarn com.netease.nimlib.apt.annotation.NIMService
-dontwarn net.zetetic.database.**
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
