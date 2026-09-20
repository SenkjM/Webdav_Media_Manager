allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// audiotags (and similar plugins) ship with compileSdk 31; AndroidX now requires 34+.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        try {
            val clazz = androidExt.javaClass
            val setCompileSdk =
                clazz.methods.firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
            if (setCompileSdk != null) {
                setCompileSdk.invoke(androidExt, 35)
            } else {
                clazz.methods
                    .firstOrNull {
                        it.name == "setCompileSdkVersion" &&
                            it.parameterCount == 1 &&
                            (it.parameterTypes[0] == Int::class.javaPrimitiveType ||
                                it.parameterTypes[0] == Int::class.java)
                    }
                    ?.invoke(androidExt, 35)
            }
        } catch (_: Throwable) {
            // Best-effort; CI will surface remaining issues.
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
