import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import org.gradle.process.ExecOperations
import javax.inject.Inject

// Packages SpaceStateKit for Android: the Swift package in this directory is
// cross-compiled with the Swift SDK for Android, and swift-java's generated
// Java bindings, its SwiftKitCore runtime and all needed .so files go into one AAR.

plugins {
    id("com.android.library") version "9.4.1"
}

val swiftSdk = providers.gradleProperty("swiftSdk").orElse("swift-6.4.0-RELEASE_android")
val swiftSdkRoot = providers.gradleProperty("swiftSdkRoot").orElse(
    "${System.getProperty("user.home")}/.swiftpm/swift-sdks/swift-6.4.0-RELEASE_android.artifactbundle/swift-android/swift-resources/usr/lib"
)
val androidApi = 28

/** ABI to Swift architecture. */
val androidAbis = mapOf("arm64-v8a" to "aarch64", "x86_64" to "x86_64")

/** The Swift runtime the bridge needs, found with readelf; libz and liblog come with Android. */
val swiftRuntime = listOf(
    "libBlocksRuntime.so", "libFoundation.so", "libFoundationEssentials.so",
    "libFoundationInternationalization.so", "libFoundationNetworking.so", "lib_FoundationICU.so",
    "libdispatch.so", "libswiftAndroid.so", "libswiftCore.so", "libswiftDispatch.so",
    "libswiftObservation.so", "libswiftSynchronization.so", "libswift_Builtin_float.so",
    "libswift_Concurrency.so", "libswift_RegexParser.so", "libswift_StringProcessing.so", "libswift_math.so",
)

android {
    namespace = "net.grafixmafia.spacestatekit"
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    defaultConfig {
        minSdk = androidApi
        consumerProguardFiles("consumer-rules.pro")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

abstract class SwiftBuild @Inject constructor(private val exec: ExecOperations) : DefaultTask() {
    @get:Input abstract val sdk: Property<String>
    @get:Input abstract val triple: Property<String>
    @get:InputFiles @get:PathSensitive(PathSensitivity.RELATIVE) abstract val sources: ConfigurableFileCollection
    @get:Internal abstract val packageDir: DirectoryProperty
    @get:OutputDirectory abstract val productsDir: DirectoryProperty

    @TaskAction
    fun build() {
        exec.exec {
            workingDir = packageDir.get().asFile
            commandLine(
                "swift", "build", "-c", "release",
                "--swift-sdk", sdk.get(), "--triple", triple.get(),
                // swift-syntax prebuilts break with Swift 6.2+ (swiftlang/swift-java#418);
                // the jextract plugin writes outside the sandbox.
                "--disable-experimental-prebuilts", "--disable-sandbox",
            )
        }
    }
}

abstract class JniLibs : DefaultTask() {
    @get:Input abstract val abis: MapProperty<String, String>
    @get:Input abstract val runtime: ListProperty<String>
    @get:Input abstract val sdkRoot: Property<String>
    /** The Swift builds' products, so a changed library is copied again. */
    @get:InputFiles @get:PathSensitive(PathSensitivity.RELATIVE) abstract val products: ConfigurableFileCollection
    @get:Internal abstract val packageDir: DirectoryProperty
    @get:Internal abstract val ndkDir: DirectoryProperty
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @get:Inject abstract val fs: FileSystemOperations

    @TaskAction
    fun copy() {
        fs.delete { delete(outputDir) }
        for ((abi, arch) in abis.get()) {
            val target = outputDir.dir(abi).get().asFile
            fs.copy {
                from(packageDir.dir(".build/out/Products/Release-android-$arch")) {
                    include("libSpaceStateKitAndroid.so", "libSwiftJava.so")
                }
                from("${sdkRoot.get()}/swift-$arch/android") { include(runtime.get()) }
                from(ndkDir.dir("toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$arch-linux-android")) {
                    include("libc++_shared.so")
                }
                into(target)
            }
            val missing = (runtime.get() + listOf("libSpaceStateKitAndroid.so", "libSwiftJava.so", "libc++_shared.so"))
                .filterNot { target.resolve(it).isFile }
            check(missing.isEmpty()) { "Missing native libraries for $abi: $missing" }
        }
    }
}

val swiftBuilds = androidAbis.map { (abi, arch) ->
    tasks.register<SwiftBuild>("swiftBuild${abi.replace("-", "").replaceFirstChar(Char::uppercase)}") {
        sdk = swiftSdk
        triple = "$arch-unknown-linux-android$androidApi"
        sources.from("Package.swift", "Package.resolved", "Sources", "../Package.swift", "../Sources")
        packageDir = layout.projectDirectory
        productsDir = layout.projectDirectory.dir(".build/out/Products/Release-android-$arch")
    }
}

val jniLibs = tasks.register<JniLibs>("swiftJniLibs") {
    dependsOn(swiftBuilds)
    abis = androidAbis
    runtime = swiftRuntime
    sdkRoot = swiftSdkRoot
    products.from(swiftBuilds.map { build -> build.flatMap { it.productsDir }.map { it.asFileTree.matching { include("*.so") } } })
    packageDir = layout.projectDirectory
    ndkDir = androidComponents.sdkComponents.ndkDirectory
    outputDir = layout.buildDirectory.dir("swift/jniLibs")
}

/** The bindings jextract generated during the Swift build, and swift-java's Java runtime. */
abstract class JavaSources : DefaultTask() {
    /** The generated bindings and SwiftKitCore, so changed sources are copied again. */
    @get:InputFiles @get:PathSensitive(PathSensitivity.RELATIVE) abstract val sources: ConfigurableFileCollection
    @get:Internal abstract val packageDir: DirectoryProperty
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @get:Inject abstract val fs: FileSystemOperations

    @TaskAction
    fun copy() {
        fs.sync {
            from(packageDir.dir(".build/plugins/outputs/android/SpaceStateKitAndroid/destination/JExtractSwiftPlugin/src/generated/java"))
            from(packageDir.dir(".build/checkouts/swift-java/SwiftKitCore/src/main/java")) {
                // ThreadSafe and Unsigned document themselves with JDK Flight Recorder
                // annotations, which Android lacks; the annotations carry no behavior.
                filesMatching(listOf("**/annotations/ThreadSafe.java", "**/annotations/Unsigned.java")) {
                    filter { line ->
                        val jfr = line.startsWith("import jdk.jfr.") ||
                            line.trimStart().startsWith("@Label(") || line.trimStart().startsWith("@Description(")
                        if (jfr) "" else line
                    }
                }
            }
            into(outputDir)
            // SwiftPM checks out read-only files; later syncs must be able to replace them.
            filePermissions { user { write = true } }
        }
    }
}

val javaSources = tasks.register<JavaSources>("swiftJavaSources") {
    dependsOn(swiftBuilds)
    sources.from(
        layout.projectDirectory.dir(".build/plugins/outputs/android/SpaceStateKitAndroid/destination/JExtractSwiftPlugin/src/generated/java"),
        layout.projectDirectory.dir(".build/checkouts/swift-java/SwiftKitCore/src/main/java"),
    )
    packageDir = layout.projectDirectory
    outputDir = layout.buildDirectory.dir("swift/java")
}

androidComponents {
    onVariants { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(jniLibs, JniLibs::outputDir)
        variant.sources.java?.addGeneratedSourceDirectory(javaSources, JavaSources::outputDir)
    }
}

group = "net.grafixmafia"
version = "0.3.2"

dependencies {
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
}
