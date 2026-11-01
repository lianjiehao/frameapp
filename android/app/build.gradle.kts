plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
import java.util.Properties

// Release credentials stay outside version control in android/key.properties.
// The release variant is never allowed to fall back to the debug keystore.
val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()
if (releaseKeyPropertiesFile.exists()) {
    releaseKeyPropertiesFile.inputStream().use(releaseKeyProperties::load)
}
val requiredReleaseProperties = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
val releaseStoreFile = releaseKeyProperties.getProperty("storeFile")?.let(rootProject::file)
val hasReleaseSigning = releaseKeyPropertiesFile.exists() &&
    requiredReleaseProperties.all { !releaseKeyProperties.getProperty(it).isNullOrBlank() } &&
    releaseStoreFile?.isFile == true

android {
    namespace = "studio.framecoach.framecoach"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "studio.framecoach.framecoach"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
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
            create("release") {
                keyAlias = releaseKeyProperties["keyAlias"] as String
                keyPassword = releaseKeyProperties["keyPassword"] as String
                storeFile = rootProject.file(releaseKeyProperties["storeFile"] as String)
                storePassword = releaseKeyProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // Keep local debug installs separate from the published package.
            applicationIdSuffix = ".debug"
        }
        release {
            // Never use the debug keystore for a distributable build.
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    doLast {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Missing android/key.properties. Configure a private release keystore before building an APK or AAB."
            )
        }
    }
}

// Make the failure explicit for the common Flutter/Gradle release tasks.
tasks.configureEach {
    if (name in setOf("assembleRelease", "bundleRelease", "packageRelease", "preReleaseBuild")) {
        dependsOn(verifyReleaseSigning)
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
