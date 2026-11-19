import java.io.FileInputStream
import java.util.Properties
import java.util.zip.ZipFile as JarZipFile
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream
import org.apache.commons.compress.archivers.zip.ZipFile as UnixZipFile

// java.util.zip cannot write Unix modes, and the ffmpeg zip holds symlinks that must stay symlinks.
buildscript {
    repositories { mavenCentral() }
    dependencies { classpath("org.apache.commons:commons-compress:1.27.1") }
}

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

val ytdlAndroidVersion = "0.18.1"
val ffmpeg16kDir = layout.projectDirectory.dir("ffmpeg-16k")
val ffmpeg16kAbis = listOf("arm64-v8a", "x86_64")

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

    // libfetchr_mpv: the JNI shim MpvGuard uses to detach libmpv players.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

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
            // The patched zips from patch<Variant>FfmpegZip; app sources merge before dependencies, so ours wins.
            pickFirsts += ffmpeg16kAbis.map { "lib/$it/libffmpeg.zip.so" }
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

// Rewrites youtubedl-android's ffmpeg zip with 16 KB-aligned libwebp; see ffmpeg-16k/README.md.
abstract class PatchFfmpegZip : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val aar: ConfigurableFileCollection

    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val replacements: DirectoryProperty

    @get:Input
    abstract val abis: ListProperty<String>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun patch() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        JarZipFile(aar.singleFile).use { aarZip ->
            for (abi in abis.get()) {
                val entry = aarZip.getEntry("jni/$abi/libffmpeg.zip.so")
                    ?: throw GradleException("ffmpeg AAR has no jni/$abi/libffmpeg.zip.so")
                val upstream = File(temporaryDir, "$abi-libffmpeg.zip")
                aarZip.getInputStream(entry).use { input -> upstream.outputStream().use { input.copyTo(it) } }
                val libs = replacements.get().dir(abi).asFile.listFiles().orEmpty()
                    .filter { it.name.endsWith(".so") }.associateBy { it.name }
                if (libs.isEmpty()) throw GradleException("No replacement libraries in ffmpeg-16k/$abi")
                val swapped = mutableSetOf<String>()
                val patched = File(out, "$abi/libffmpeg.zip.so").apply { parentFile.mkdirs() }
                UnixZipFile.builder().setFile(upstream).get().use { zin ->
                    ZipArchiveOutputStream(patched).use { zout ->
                        for (e in zin.entriesInPhysicalOrder) {
                            val lib = libs[e.name.removePrefix("usr/lib/")]
                            if (lib == null || e.isUnixSymlink) {
                                zout.addRawArchiveEntry(e, zin.getRawInputStream(e))
                                continue
                            }
                            val replacement = ZipArchiveEntry(e.name).apply {
                                unixMode = e.unixMode
                                method = e.method
                                time = e.time
                            }
                            zout.putArchiveEntry(replacement)
                            lib.inputStream().use { it.copyTo(zout) }
                            zout.closeArchiveEntry()
                            swapped += lib.name
                        }
                    }
                }
                val missing = libs.keys - swapped
                if (missing.isNotEmpty()) throw GradleException("Not in the $abi ffmpeg zip: $missing")
            }
        }
    }
}

val ffmpegAar: Configuration by configurations.creating {
    isCanBeConsumed = false
    isTransitive = false
}

androidComponents {
    onVariants { variant ->
        val patch = tasks.register<PatchFfmpegZip>("patch${variant.name.replaceFirstChar(Char::uppercase)}FfmpegZip") {
            aar.from(ffmpegAar)
            replacements.set(ffmpeg16kDir)
            abis.set(ffmpeg16kAbis)
        }
        variant.sources.jniLibs?.addGeneratedSourceDirectory(patch, PatchFfmpegZip::outputDir)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation("io.github.junkfood02.youtubedl-android:library:$ytdlAndroidVersion")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:$ytdlAndroidVersion")
    implementation("io.github.junkfood02.youtubedl-android:aria2c:$ytdlAndroidVersion")
    ffmpegAar("io.github.junkfood02.youtubedl-android:ffmpeg:$ytdlAndroidVersion@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.core:core-ktx:1.18.0")

    // android.jar's org.json is a stub on the JVM.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
}

flutter {
    source = "../.."
}
