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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            project.extensions.configure<com.android.build.gradle.BaseExtension> {
                compileSdkVersion(36)
                
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }

        // Method for adding a namespace to an Android library when using Gradle 8+
        if (project.plugins.hasPlugin("com.android.library")) {
            project.extensions.configure<com.android.build.gradle.LibraryExtension> {
                defaultConfig {
                    val androidManifest = sourceSets.getByName("main").manifest.srcFile
                    if (androidManifest.exists()) {
                        val parsedManifest = groovy.xml.XmlParser().parse(androidManifest)
                        val packageName = parsedManifest.attribute("package") as? String

                        if (packageName == null && namespace == null) {
                            namespace = "com.example.pro_room_scanner"
                        }

                        if (namespace == null) {
                            namespace = project.group.toString()
                        }
                    }
                }
            }
        }
    }
    project.evaluationDependsOn(":app")
}
