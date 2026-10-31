plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStore = System.getenv("ANDROID_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val releaseAlias = System.getenv("ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword)
    .all { !it.isNullOrBlank() }
if (System.getenv("TVE_REQUIRE_RELEASE_SIGNING") == "true" && !hasReleaseSigning) {
    throw GradleException("Production release requires all four ANDROID signing environment variables")
}

android {
    namespace = "com.leos.leos_fast_video_edit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.leos.leos_fast_video_edit"

        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(24, flutter.minSdkVersion)
        ndk {
            // Replace Flutter's defaults rather than extending its three-ABI set.
            abiFilters.clear()
            abiFilters += listOf("arm64-v8a")
        }
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("production") {
                storeFile = file(releaseStore!!)
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Without credentials this is unsigned; CI builds a clearly named debug test APK.
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("production")
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

dependencies {
    implementation("androidx.media3:media3-transformer:1.11.1")
    implementation("androidx.media3:media3-effect:1.11.1")
}



