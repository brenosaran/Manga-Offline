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
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        try {
            val current = androidExt.javaClass.methods
                .firstOrNull { it.name == "getNamespace" && it.parameterCount == 0 }
                ?.invoke(androidExt)
            if (current == null) {
                val ns = "com.example." + project.name.replace('-', '_').replace('.', '_')
                androidExt.javaClass.methods
                    .firstOrNull { it.name == "setNamespace" && it.parameterCount == 1 }
                    ?.invoke(androidExt, ns)
            }
            val compileSdkSetters = listOf("setCompileSdkVersion", "setCompileSdk", "compileSdkVersion")
            for (name in compileSdkSetters) {
                val setter = androidExt.javaClass.methods.firstOrNull {
                    it.name == name &&
                        it.parameterCount == 1 &&
                        it.parameterTypes[0] == Int::class.javaPrimitiveType
                }
                if (setter != null) {
                    setter.invoke(androidExt, 36)
                    break
                }
            }
        } catch (_: Exception) {
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
