# R8 混淆/收缩规则

# OkHttp 会按运行环境反射加载可选的 TLS 平台实现，这些依赖在 Android 上不存在，
# 属于"仅在对应平台才会用到"的引用，直接忽略即可（否则 release 打包报 Missing class）。
-dontwarn org.openjsse.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.ietf.jgss.**
-dontwarn com.android.org.conscrypt.**
-dontwarn sun.security.**
-dontwarn com.google.android.gms.**

# OkHttp / Okio 常规忽略项
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
