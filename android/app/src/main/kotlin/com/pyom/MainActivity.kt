
package com.pyom

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipFile

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentProcess: Process? = null
    private val isSetupCancelled = AtomicBoolean(false)
    private val executor = Executors.newCachedThreadPool()

    // ── Storage paths ──────────────────────────────────────────────────────
    private val extDir get() = getExternalFilesDir(null) ?: filesDir
    private val envRoot get() = File(extDir, "linux_env")
    private val binDir get() = File(filesDir, "bin")
    private val prootVersionFile get() = File(binDir, "proot.version")
    private val envConfigFile get() = File(filesDir, "env_config.json")

    // --- FIX: Paths for bundled (in nativeLibraryDir) and extracted (in filesDir) proot ---
    private val prootBundledBin get() = File(applicationInfo.nativeLibraryDir, "libproot.so")
    private val prootExtractedBin get() = File(binDir, "proot")

    private val prootBin: File
        get() {
            // Prefer the manually extracted binary if it exists and is executable
            return if (prootExtractedBin.exists() && prootExtractedBin.canExecute()) prootExtractedBin
            else prootBundledBin
        }

    private val rootfsSources = mapOf(
        "alpine" to listOf("https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz"),
        "ubuntu" to listOf("https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.3-base-arm64.tar.gz"),
    )

    private var eventSink: EventChannel.EventSink? = null
    private val CHANNEL = "com.pyom/linux_environment"
    private val OUTPUT_CHANNEL = "com.pyom/process_output"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, OUTPUT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(a: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
                override fun onCancel(a: Any?) { eventSink = null }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setupEnvironment" -> {
                        isSetupCancelled.set(false)
                        val distro = call.argument<String>("distro") ?: "alpine"
                        val envId = call.argument<String>("envId") ?: "alpine"
                        executor.execute { setupEnvironment(distro, envId, result) }
                    }
                    "cancelSetup" -> { isSetupCancelled.set(true); result.success(null) }
                    "executeCommand" -> executeCommand(call, result)
                    "isEnvironmentInstalled" -> {
                        val envId = call.argument<String>("envId") ?: ""
                        result.success(isEnvironmentInstalled(envId))
                    }
                    "getInstalledEnvironment" -> result.success(getInstalledEnvironment())
                    "listEnvironments" -> result.success(listEnvironments())
                    "deleteEnvironment" -> {
                        val envId = call.argument<String>("envId") ?: ""
                        val deleted = deleteEnvironment(envId)
                        result.success(deleted)
                    }
                    "getStorageInfo" -> {
                        val prootCheckError = ensureProotBinary()
                        result.success(mapOf(
                            "filesDir" to filesDir.absolutePath,
                            "envRoot" to envRoot.absolutePath,
                            "freeSpaceMB" to (extDir.freeSpace / 1048576L),
                            "totalSpaceMB" to (extDir.totalSpace / 1048576L),
                            "prootVersion" to (prootVersionFile.takeIf { it.exists() }?.readText()?.trim() ?: "bundled"),
                            "prootPath" to prootBin.absolutePath,
                            "prootExists" to (prootCheckError == null),
                            "prootError" to prootCheckError
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    // --- FIX: APK EXTRACTION FALLBACK & BETTER ERROR MESSAGE ---
    private fun ensureProotBinary(): String? {
        // Check 1: If prootBin (either extracted or bundled) is ready, we're good.
        if (prootBin.exists() && prootBin.canExecute()) {
            return null // Success
        }

        // Check 2: Try to extract from APK as a fallback.
        // This is crucial for AGP 8+ where useLegacyPackaging=false is default.
        try {
            val apkPath = applicationInfo.sourceDir
            ZipFile(apkPath).use { zip ->
                val entry = zip.getEntry("lib/arm64-v8a/libproot.so")
                    ?: return "FATAL: lib/arm64-v8a/libproot.so not found inside APK ($apkPath)."

                binDir.mkdirs()
                zip.getInputStream(entry).use { input ->
                    prootExtractedBin.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                prootExtractedBin.setExecutable(true, false)

                // If extraction was successful, return null (success)
                if (prootExtractedBin.exists() && prootExtractedBin.canExecute()) {
                    prootVersionFile.writeText("bundled-extracted")
                    return null // Success
                }
            }
        } catch (e: Exception) {
            // If extraction fails, we'll report it in the final error message.
        }
        
        // Check 3: If we're still here, both checks failed. Generate a detailed error report.
        val nativeLibDir = File(applicationInfo.nativeLibraryDir)
        val nativeLibFiles = nativeLibDir.listFiles()?.joinToString(", ") { it.name } ?: "is empty or does not exist"

        return """
        FATAL: proot binary not found or not executable.
        - Bundled Path: ${prootBundledBin.absolutePath} (exists: ${prootBundledBin.exists()})
        - Extracted Path: ${prootExtractedBin.absolutePath} (exists: ${prootExtractedBin.exists()})
        - APK Path: ${applicationInfo.sourceDir}
        - Native Lib Dir: ${nativeLibDir.absolutePath}
        - Native Lib Contents: [$nativeLibFiles]
        
        This usually happens with newer Android Gradle Plugin versions.
        Please ensure 'android.packaging.jniLibs.useLegacyPackaging = true' is in your app/build.gradle file.
        """.trimIndent()
    }

    private fun isEnvironmentInstalled(envId: String): Boolean {
        val envDir = File(envRoot, envId)
        if (!envDir.exists()) return false
        val hasShell = listOf(File(envDir, "bin/sh"), File(envDir, "bin/bash")).any { it.exists() }
        val hasOsRelease = File(envDir, "etc/os-release").exists()
        return hasShell || hasOsRelease
    }

    private fun getInstalledEnvironment(): Map<String, Any>? {
        return listEnvironments().firstOrNull { it["exists"] as Boolean }
    }

    private fun deleteEnvironment(envId: String): Boolean {
        return try {
            File(envRoot, envId).takeIf { it.exists() }?.deleteRecursively()
            envConfigFile.takeIf { it.exists() }?.delete()
            true
        } catch (e: Exception) { false }
    }
    
    private fun listEnvironments(): List<Map<String, Any>> {
        if (!envRoot.exists()) return emptyList()
        return envRoot.listFiles()?.filter { it.isDirectory }?.map { dir ->
            mapOf(
                "id" to dir.name,
                "path" to dir.absolutePath,
                "exists" to isEnvironmentInstalled(dir.name),
            )
        } ?: emptyList()
    }

    private fun sendProgress(msg: String, progress: Double) {
        mainHandler.post {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("onSetupProgress", mapOf("message" to msg, "progress" to progress))
            }
        }
    }

    private fun setupEnvironment(distro: String, envId: String, result: MethodChannel.Result) {
        try {
            val envDir = File(envRoot, envId)
            if (isEnvironmentInstalled(envId)) {
                sendProgress("✅ Environment already installed!", 1.0)
                mainHandler.post { result.success(mapOf("success" to true, "alreadyInstalled" to true)) }
                return
            }
            envDir.mkdirs()

            val prootError = ensureProotBinary()
            if (prootError != null) {
                mainHandler.post { result.error("SETUP_ERROR", prootError, null) }
                return
            }
            sendProgress("✅ proot ready", 0.05)
            if (isSetupCancelled.get()) { mainHandler.post { result.error("CANCELLED", "Cancelled", null) }; return }

            sendProgress("Downloading $distro rootfs…", 0.10)
            val tarFile = File(extDir, "rootfs_${envId}.tar.gz")
            val sources = rootfsSources[distro] ?: rootfsSources["alpine"]!!
            downloadWithProgress(sources[0], tarFile, 0.10, 0.60)
            if (isSetupCancelled.get()) { tarFile.delete(); mainHandler.post { result.error("CANCELLED", "Cancelled", null) }; return }

            sendProgress("Extracting rootfs…", 0.62)
            extractTarGz(tarFile, envDir)
            tarFile.delete()
            if (isSetupCancelled.get()) { mainHandler.post { result.error("CANCELLED", "Cancelled", null) }; return }

            sendProgress("Configuring environment…", 0.75)
            File(envDir, "etc/resolv.conf").writeText("nameserver 8.8.8.8\nnameserver 1.1.1.1\n")
            listOf("tmp", "root", "proc", "sys", "dev").forEach { File(envDir, it).mkdirs() }

            sendProgress("Installing Python & build tools…", 0.78)
            val installCmd = if (distro == "ubuntu") {
                "export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -y -qq python3 python3-pip python3-dev gcc g++ make curl wget && pip3 install --upgrade pip setuptools wheel"
            } else {
                "apk add --no-cache python3 py3-pip python3-dev gcc musl-dev make curl wget"
            }
            runCommandInProot(envId, installCmd, "/", 600_000)

            saveEnvConfig(envId, distro)
            sendProgress("✅ Environment ready!", 1.0)
            mainHandler.post { result.success(mapOf("success" to true)) }

        } catch (e: Exception) {
            mainHandler.post { result.error("SETUP_ERROR", e.message ?: "Unknown error", null) }
        }
    }
    
    private fun saveEnvConfig(envId: String, distro: String) {
        try {
            val config = """{"envId": "$envId", "distro": "$distro", "installedAt": ${System.currentTimeMillis()}}"""
            envConfigFile.writeText(config)
        } catch (e: Exception) { /* Ignore */ }
    }

    private fun executeCommand(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val envId = call.argument<String>("environmentId") ?: getInstalledEnvironment()?.get("id") as String? ?: ""
                val command = call.argument<String>("command") ?: ""
                val workingDir = call.argument<String>("workingDir") ?: "/"
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 300000

                if (envId.isEmpty()) {
                    mainHandler.post { result.error("EXEC_ERROR", "No Linux environment found.", null) }
                    return@execute
                }
                mainHandler.post { result.success(runCommandInProot(envId, command, workingDir, timeoutMs)) }
            } catch (e: Exception) {
                mainHandler.post { result.error("EXEC_ERROR", e.message, null) }
            }
        }
    }

    private fun runCommandInProot(envId: String, command: String, workingDir: String, timeoutMs: Int): Map<String, Any> {
        val prootError = ensureProotBinary()
        if (prootError != null) {
            return mapOf("stdout" to "", "exitCode" to -1, "stderr" to prootError)
        }

        val envDir = File(envRoot, envId)
        if (!envDir.exists()) {
            return mapOf("stdout" to "", "exitCode" to -1, "stderr" to "Environment directory not found: ${envDir.absolutePath}")
        }
        
        val shell = listOf(
            "/bin/bash", "/bin/sh",
            "/usr/bin/bash", "/usr/bin/sh",
            "/usr/local/bin/bash", "/usr/local/bin/sh"
        ).firstOrNull { File(envDir, it.drop(1)).let { f -> f.exists() || java.nio.file.Files.isSymbolicLink(f.toPath()) } }
            ?: return mapOf("stdout" to "", "exitCode" to -1, "stderr" to "No valid shell found in rootfs. Try reinstalling the environment.")

        val cmd = listOf(
            prootBin.absolutePath,
            "--kill-on-exit", "-k", "5.4.0", "--link2symlink", "-r", envDir.absolutePath,
            "-w", workingDir, "-b", "/dev", "-b", "/proc", "-b", "/sys",
            "-b", "${filesDir.absolutePath}:/data_internal", "-0",
            shell, "-c", command
        )

        val pb = ProcessBuilder(cmd).apply {
            directory(filesDir)
            redirectErrorStream(false)
            environment().apply {
                put("HOME", "/root")
                put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
                put("LANG", "C.UTF-8")
                put("LC_ALL", "C.UTF-8")
                put("TERM", "xterm-256color")
                put("TMPDIR", File(envDir, "tmp").absolutePath)
                put("PROOT_TMP_DIR", File(envDir, "tmp").absolutePath)
                put("PROOT_NO_SECCOMP", "1")
                put("PROOT_LOADER", prootBin.absolutePath)
                put("LD_PRELOAD", "")
            }
        }

        try {
            val process = pb.start(); currentProcess = process
            val stdout = StringBuilder()
            val stderr = StringBuilder()

            val t1 = Thread { process.inputStream.bufferedReader().lines().forEach { stdout.append(it).append("\n"); mainHandler.post { eventSink?.success(it) } } }
            val t2 = Thread { process.errorStream.bufferedReader().lines().forEach { stderr.append(it).append("\n"); mainHandler.post { eventSink?.success("[err] $it") } } }
            t1.start(); t2.start()

            val done = process.waitFor(timeoutMs.toLong(), java.util.concurrent.TimeUnit.MILLISECONDS)
            t1.join(1000); t2.join(1000)

            return if (done) {
                mapOf("stdout" to stdout.toString(), "stderr" to stderr.toString(), "exitCode" to process.exitValue())
            } else {
                process.destroyForcibly()
                mapOf("stdout" to stdout.toString(), "stderr" to "Command timed out after ${timeoutMs}ms", "exitCode" to -1)
            }
        } catch (e: Exception) {
            return mapOf("stdout" to "", "stderr" to "Process execution error: ${e.message}", "exitCode" to -1)
        }
    }

    private fun downloadWithProgress(urlStr: String, dest: File, progressStart: Double, progressEnd: Double) {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        conn.connect()
        val total = conn.contentLengthLong.toDouble()
        var downloaded = 0L
        conn.inputStream.use { input ->
            FileOutputStream(dest).use { output ->
                val buf = ByteArray(8192)
                var n: Int
                while (input.read(buf).also { n = it } != -1) {
                    if (isSetupCancelled.get()) throw Exception("Download cancelled")
                    output.write(buf, 0, n)
                    downloaded += n
                    val p = progressStart + (downloaded / total) * (progressEnd - progressStart)
                    sendProgress("Downloading… ${(downloaded / 1048576.0).toInt()}MB / ${(total / 1048576.0).toInt()}MB", p)
                }
            }
        }
    }

    private fun extractTarGz(tarFile: File, destDir: File) {
        TarArchiveInputStream(GzipCompressorInputStream(BufferedInputStream(tarFile.inputStream()))).use { tar ->
            var entry = tar.nextEntry
            while (entry != null) {
                if (isSetupCancelled.get()) throw Exception("Extraction cancelled")
                if (!tar.canReadEntryData(entry)) { entry = tar.nextEntry; continue }
                val target = File(destDir, entry.name.removePrefix("./"))
                if (!target.canonicalPath.startsWith(destDir.canonicalPath)) { continue }
                when {
                    entry.isDirectory -> target.mkdirs()
                    entry.isSymbolicLink -> {
                        try {
                            val targetPath = target.toPath()
                            val linkTarget = java.nio.file.Paths.get(entry.linkName)
                            // Delete existing file/link if present
                            if (java.nio.file.Files.exists(targetPath, java.nio.file.LinkOption.NOFOLLOW_LINKS)) {
                                java.nio.file.Files.delete(targetPath)
                            }
                            target.parentFile?.mkdirs()
                            java.nio.file.Files.createSymbolicLink(targetPath, linkTarget)
                        } catch (e: Exception) {
                            // Fallback: physically copy the target file
                            try {
                                val linkSource = File(destDir, entry.linkName)
                                if (linkSource.exists() && !linkSource.isDirectory) {
                                    target.parentFile?.mkdirs()
                                    linkSource.copyTo(target, overwrite = true)
                                }
                            } catch (_: Exception) {}
                        }
                    }
                    else -> {
                        target.parentFile?.mkdirs()
                        FileOutputStream(target).use { tar.copyTo(it) }
                        if (entry.mode and 0b001001001 != 0) target.setExecutable(true, false)
                    }
                }
                entry = tar.nextEntry
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        currentProcess?.destroyForcibly()
        executor.shutdown()
    }
}
