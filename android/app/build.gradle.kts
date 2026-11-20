plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.marcador_asistencia"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Habilitar Desugaring de librerías para flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.marcador_asistencia"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// -------------------------------------------------------------
// DEPENDENCIAS NATIVAS DE ANDROID (DESUGARING >= 2.1.4)
// -------------------------------------------------------------
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// -------------------------------------------------------------
// FORZAR DEPENDENCIAS COMPATIBLES CON ANDROID 35 / COMPILE SDK 36
// -------------------------------------------------------------
configurations.all {
    resolutionStrategy {
        force("androidx.camera:camera-core:1.3.4")
        force("androidx.camera:camera-camera2:1.3.4")
        force("androidx.camera:camera-lifecycle:1.3.4")
        force("androidx.camera:camera-video:1.3.4")
        force("androidx.core:core:1.15.0")
        force("androidx.core:core-ktx:1.15.0")
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

