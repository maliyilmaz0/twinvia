import org.gradle.api.artifacts.ConfigurationContainer

// AGP 9.4.1 still requests vulnerable build-time crypto, XML and JWT libraries.
// Minimum compatible patch lines from the reviewed advisories; newer versions win.
val securityMinimums =
    mapOf(
        "org.bouncycastle:bcprov-jdk18on" to "1.86",
        "org.bouncycastle:bcpkix-jdk18on" to "1.86",
        "org.bouncycastle:bcutil-jdk18on" to "1.86",
        "org.bitbucket.b_c:jose4j" to "0.9.7",
        "org.jdom:jdom2" to "2.0.6.1",
        "org.apache.commons:commons-compress" to "1.27.1",
        "org.apache.commons:commons-lang3" to "3.18.0",
        "org.apache.httpcomponents:httpclient" to "4.5.14",
        "com.google.protobuf:protobuf-java" to "3.25.5",
        "com.google.protobuf:protobuf-kotlin" to "3.25.5",
        "com.google.guava:guava" to "33.7.2",
    )
val nettyMinimum = "4.1.137.Final"

fun compareNumericVersions(left: String, right: String): Int {
    fun numericParts(version: String) =
        version
            .split('.')
            .takeWhile { it.firstOrNull()?.isDigit() == true }
            .map { it.takeWhile(Char::isDigit).toInt() }
    val a = numericParts(left)
    val b = numericParts(right)
    require(a.isNotEmpty() && b.isNotEmpty()) {
        "Cannot compare dependency versions: $left / $right"
    }
    for (i in 0 until maxOf(a.size, b.size)) {
        val difference = a.getOrElse(i) { 0 }.compareTo(b.getOrElse(i) { 0 })
        if (difference != 0) return difference
    }
    return 0
}

fun minimumFor(group: String?, name: String): String? =
    if (group == "io.netty") nettyMinimum else securityMinimums["$group:$name"]

fun ConfigurationContainer.applySecurityMinimums() {
    configureEach {
        resolutionStrategy.eachDependency {
            val minimum = minimumFor(requested.group, requested.name)
            val current = requested.version
            if (
                minimum != null &&
                    !current.isNullOrEmpty() &&
                    compareNumericVersions(current, minimum) < 0
            ) {
                val selected =
                    if (requested.group == "com.google.guava" && requested.name == "guava") {
                        minimum + if (current.endsWith("-android")) "-android" else "-jre"
                    } else minimum
                useVersion(selected)
                because("Reviewed security patch floor; see docs/github-security.md")
            }
        }
    }
}

gradle.beforeProject {
    buildscript.configurations.applySecurityMinimums()
    configurations.applySecurityMinimums()
    tasks.register("verifyBuildDependencySecurity") {
        group = "verification"
        description = "Check the resolved plugin classpath against reviewed security patch floors."
        doLast {
            val artifacts =
                buildscript.configurations
                    .getByName("classpath")
                    .resolvedConfiguration
                    .resolvedArtifacts
            artifacts.forEach { artifact ->
                val id = artifact.moduleVersion.id
                val minimum = minimumFor(id.group, id.name)
                if (minimum != null) {
                    check(compareNumericVersions(id.version, minimum) >= 0) {
                        "Vulnerable build dependency: $id"
                    }
                    println("Verified build dependency: $id")
                }
            }
        }
    }
}
