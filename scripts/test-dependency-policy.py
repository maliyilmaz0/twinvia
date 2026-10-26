#!/usr/bin/env python3
"""Resolve real vulnerable fixture dependencies to test the Gradle security policy."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
fixture = ROOT / '.artifacts/dependency-policy-test'
fixture.mkdir(parents=True, exist_ok=True)
policy = ROOT / 'apps/android/gradle/dependency-security.settings.gradle.kts'
(fixture / 'settings.gradle.kts').write_text(
    'rootProject.name = "DependencySecurityRegression"\n'
    f'apply(from = file("{policy.as_posix()}"))\n')
(fixture / 'build.gradle.kts').write_text('''
buildscript {
    repositories { mavenCentral() }
    dependencies {
        classpath("org.bouncycastle:bcprov-jdk18on:1.79")
        classpath("org.jdom:jdom2:2.0.6")
        classpath("org.apache.commons:commons-compress:1.28.0")
    }
}
repositories { mavenCentral() }
val probe = configurations.create("securityProbe")
dependencies {
    add(probe.name, "io.netty:netty-handler:4.1.110.Final")
    add(probe.name, "io.netty:netty-codec-http2:4.1.93.Final")
}
tasks.register("testSecurityPolicy") {
    dependsOn("verifyBuildDependencySecurity")
    doLast {
        val buildIds = buildscript.configurations.getByName("classpath")
            .resolvedConfiguration.resolvedArtifacts.map { it.moduleVersion.id }
        check(buildIds.any { it.name == "bcprov-jdk18on" && it.version == "1.86" })
        check(buildIds.any { it.name == "jdom2" && it.version == "2.0.6.1" })
        // A newer compatible request must never be downgraded to the floor.
        check(buildIds.any { it.name == "commons-compress" && it.version == "1.28.0" })
        val netty = probe.resolvedConfiguration.resolvedArtifacts.map { it.moduleVersion.id }
            .filter { it.group == "io.netty" }
        check(netty.isNotEmpty())
        check(netty.all { it.version == "4.1.137.Final" })
        println("Dependency policy regression passed: plugin patches, Netty alignment, no downgrade.")
    }
}
''')
subprocess.run([str(ROOT / 'apps/android/gradlew'), '-p', str(fixture),
                'testSecurityPolicy', '--console=plain'], check=True)
