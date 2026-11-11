import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads android/key.properties (gitignored). Without it,
// release builds fall back to the debug key so `flutter run --release` works.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}

fun getGitHash(): String = try {
    providers.exec {
        commandLine("git", "rev-parse", "--short", "HEAD")
    }.standardOutput.asText.get().trim().ifEmpty { "unknown" }
} catch (e: Exception) {
    "unknown"
}

fun getFlutterVersionName(): String {
    val pubspecFile = rootProject.file("../pubspec.yaml")
    if (pubspecFile.exists()) {
        val versionLine = pubspecFile.readLines().firstOrNull { it.startsWith("version:") }
        if (versionLine != null) {
            return versionLine.substringAfter("version:").trim().substringBefore("+")
        }
    }
    return "0.0.0"
}

android {
    namespace = "com.defo.fetchr"
    // The SDK ships API 37 as platform "android-37.0"; plain `compileSdk = 37` looks for "android-37".
    compileSdk {
        version = release(37) {
            minorApiLevel = 0
        }
    }
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Backports java.time for older Android.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.defo.fetchr"
        // sentry_flutter 10 needs API 26.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as? String
                    ?: error("key.properties: keyAlias missing")
                keyPassword = keystoreProperties["keyPassword"] as? String
                    ?: error("key.properties: keyPassword missing")
                storeFile = file(
                    keystoreProperties["storeFile"] as? String
                        ?: error("key.properties: storeFile missing"),
                )
                storePassword = keystoreProperties["storePassword"] as? String
                    ?: error("key.properties: storePassword missing")
            }
        }
    }

    packaging {
        jniLibs {
            // youtubedl-android runs libpython, ffmpeg and aria2c from nativeLibraryDir, so the .so files must be extracted.
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Names Gradle's APKs Fetchr-<version>-<hash>-<abi>-<buildType>.apk under
// build/app/outputs/apk/; Flutter's copies in flutter-apk/ keep its own names.
base {
    archivesName.set("Fetchr-${getFlutterVersionName()}-${getGitHash()}")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:aria2c:0.18.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.core:core-ktx:1.18.0")

    // android.jar's org.json is a stub on the JVM.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
}

flutter {
    source = "../.."
}
