# Swift calls into the generated bindings and SwiftKitCore over JNI by name.
-keep class net.grafixmafia.spacestatekit.bridge.** { *; }
-keep class org.swift.swiftkit.** { *; }
# Two SwiftKitCore annotations reference JDK Flight Recorder, which Android lacks.
-dontwarn jdk.jfr.**
