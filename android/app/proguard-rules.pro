# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep FileProvider and MainActivity MethodChannel
-keep class androidx.core.content.FileProvider { *; }
-keep class com.domainlock.webview.webview_domain_lock.** { *; }

# WebView & JS Interfaces
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

-dontwarn io.flutter.**
