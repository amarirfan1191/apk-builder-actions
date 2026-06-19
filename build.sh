#!/usr/bin/env bash
set -e

echo "BUILD_TYPE=$BUILD_TYPE APP_NAME=$APP_NAME APP_URL=$APP_URL"

if [ "$BUILD_TYPE" = "url" ]; then
  PKG="com.apkbot.$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | head -c20)"
  mkdir -p webview-app/app/src/main/java/com/apkbot/app
  mkdir -p webview-app/app/src/main/res/layout
  mkdir -p webview-app/app/src/main/res/values
  mkdir -p webview-app/gradle/wrapper

  printf 'rootProject.name = "WebViewApp"\ninclude ":app"\n' > webview-app/settings.gradle
  printf 'buildscript {\n  repositories { google(); mavenCentral() }\n  dependencies { classpath "com.android.tools.build:gradle:8.2.2" }\n}\nallprojects { repositories { google(); mavenCentral() } }\n' > webview-app/build.gradle
  printf 'android.useAndroidX=true\norg.gradle.daemon=false\n' > webview-app/gradle.properties
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.4-bin.zip\n' > webview-app/gradle/wrapper/gradle-wrapper.properties

  cat > webview-app/app/build.gradle <<APKEOF
plugins { id 'com.android.application' }
android {
  namespace "$PKG"
  compileSdk 34
  defaultConfig { applicationId "$PKG"; minSdk 21; targetSdk 34; versionCode 1; versionName "1.0" }
  buildTypes { release { minifyEnabled false; signingConfig signingConfigs.debug } }
  compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
}
dependencies { implementation 'androidx.appcompat:appcompat:1.6.1' }
APKEOF

  cat > webview-app/app/src/main/AndroidManifest.xml <<APKEOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
  <application android:allowBackup="true" android:label="$APP_NAME" android:usesCleartextTraffic="true" android:theme="@style/Theme.AppCompat.NoActionBar">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
APKEOF

  cat > webview-app/app/src/main/java/com/apkbot/app/MainActivity.java <<APKEOF
package com.apkbot.app;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
public class MainActivity extends Activity {
  private WebView wv;
  @SuppressLint("SetJavaScriptEnabled")
  @Override protected void onCreate(Bundle b) {
    super.onCreate(b);
    wv = new WebView(this);
    WebSettings s = wv.getSettings();
    s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true);
    s.setLoadWithOverviewMode(true); s.setUseWideViewPort(true);
    wv.setWebViewClient(new WebViewClient());
    wv.loadUrl("$APP_URL");
    setContentView(wv);
  }
  @Override public void onBackPressed() { if (wv.canGoBack()) wv.goBack(); else super.onBackPressed(); }
}
APKEOF

  printf '<?xml version="1.0" encoding="utf-8"?>\n<resources><string name="app_name">%s</string></resources>\n' "$APP_NAME" > webview-app/app/src/main/res/values/strings.xml

  cd webview-app
  gradle wrapper && chmod +x gradlew
  ./gradlew assembleRelease --no-daemon 2>&1 | tail -80
  find . -name "*.apk" -exec cp {} ../output.apk \;

elif [ "$BUILD_TYPE" = "zip" ]; then
  [ -f "upload.zip" ] || (echo "upload.zip missing!" && exit 1)
  unzip -o upload.zip -d zip-project

  FLUTTER_DIR=$(find zip-project -name "pubspec.yaml" | head -1 | xargs dirname 2>/dev/null || echo "")
  GRADLE_DIR=$(find zip-project -name "gradlew" | head -1 | xargs dirname 2>/dev/null || echo "")

  if [ -n "$FLUTTER_DIR" ]; then
    echo "Flutter project: $FLUTTER_DIR"
    sudo snap install flutter --classic 2>/dev/null || true
    export PATH="$HOME/snap/flutter/common/flutter/bin:$PATH"
    cd "$FLUTTER_DIR"
    flutter pub get && flutter build apk --release --no-tree-shake-icons
    find . -name "*.apk" | head -1 | xargs -I{} cp {} $GITHUB_WORKSPACE/output.apk
  elif [ -n "$GRADLE_DIR" ]; then
    echo "Gradle project: $GRADLE_DIR"
    cd "$GRADLE_DIR" && chmod +x gradlew
    ./gradlew assembleRelease --no-daemon 2>&1 | tail -80
    find . -name "*.apk" | head -1 | xargs -I{} cp {} $GITHUB_WORKSPACE/output.apk
  else
    echo "Unknown project type! (no pubspec.yaml or gradlew found)" && exit 1
  fi
else
  echo "Unknown BUILD_TYPE: $BUILD_TYPE" && exit 1
fi

ls -lh output.apk
echo "Build complete!"
