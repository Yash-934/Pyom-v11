
package com.pyom

import android.content.ContentValues
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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
import okhttp3.OkHttpClient
import okhttp3.Request
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipFile

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentProcess: Process? = null
    private val isSetupCancelled = AtomicBoolean(false)

    // ── OkHttpClient — reliable DNS, redirects, retries ───────────────────
    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
            .build()
    }
    private val executor = Executors.newCachedThreadPool()

    // ── Storage paths ──────────────────────────────────────────────────────
    private val extDir get() = getExternalFilesDir(null) ?: filesDir
    private val envRoot get() = File(extDir, "linux_env")

    // ⚠️ CRITICAL EXEC PATH STRATEGY:
    // Android has MS_NOEXEC on /data AND FUSE noexec on /sdcard on many devices.
    // The ONLY guaranteed exec-safe locations are:
    //   1. nativeLibraryDir  — set by Android package manager (ideal, needs libproot.so in jniLibs)
    //   2. codeCacheDir      — /data/user/0/pkg/code_cache/ — Android marks this exec-safe for JIT
    // We try both, codeCacheDir is our reliable fallback.
    private val binDir get() = File(codeCacheDir, "bin")
    private val prootVersionFile get() = File(binDir, "proot.version")
    private val envConfigFile get() = File(filesDir, "env_config.json")

    // --- FIX: Paths for bundled (in nativeLibraryDir) and extracted (in filesDir) proot ---
    private val prootBundledBin get() = File(applicationInfo.nativeLibraryDir, "libproot.so")
    private val prootExtractedBin get() = File(binDir, "proot")

    private val prootBin: File
        get() {
            // Check alt-path saved during setup (Priority 4 fallback)
            val versionTxt = prootVersionFile.takeIf { it.exists() }?.readText()?.trim() ?: ""
            if (versionTxt.startsWith("alt-path:")) {
                val altFile = File(versionTxt.removePrefix("alt-path:"))
                if (altFile.exists()) return altFile
            }
            // Prefer nativeLibraryDir (always exec-safe, no extraction needed)
            if (prootBundledBin.exists()) return prootBundledBin
            // Fall back to extracted binary in codeCacheDir
            return prootExtractedBin
        }

    private val rootfsSources = mapOf(
        "alpine" to listOf(
            // Mirror 1: Official Alpine CDN
            "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz",
            // Mirror 2: Tsinghua (China/Asia fast)
            "https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz",
            // Mirror 3: USTC China
            "https://mirrors.ustc.edu.cn/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz",
            // Mirror 4: NJU China
            "https://mirror.nju.edu.cn/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz",
        ),
        "ubuntu" to listOf(
            // Mirror 1: Official Ubuntu CDImage
            "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.3-base-arm64.tar.gz",
            // Mirror 2: Tsinghua mirror
            "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.3-base-arm64.tar.gz",
            // Mirror 3: USTC
            "https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.3-base-arm64.tar.gz",
            // Mirror 4: Aliyun
            "https://mirrors.aliyun.com/ubuntu-cdimage/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.3-base-arm64.tar.gz",
        ),
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
    
    // ─── TEST IF A BINARY IS ACTUALLY EXECUTABLE ──────────────────────────────
    // canExecute() is UNRELIABLE on Android 10+ (FUSE filesystem returns wrong result).
    // Instead, actually try to execute the binary and check exit code.
    private fun isActuallyExecutable(file: File): Boolean {
        if (!file.exists()) return false
        return try {
            val proc = ProcessBuilder(file.absolutePath, "--version")
                .redirectErrorStream(true)
                .start()
            // proot --version exits 0 or 1 — both mean it ran. 
            // Only error=13 (EACCES) or error=8 (ENOEXEC) means NOT executable.
            val exited = proc.waitFor(3, TimeUnit.SECONDS)
            if (!exited) { proc.destroyForcibly(); true } // still running = executable
            val code = proc.exitValue()
            code != 126 && code != 127 // 126=not executable, 127=not found
        } catch (e: Exception) {
            val msg = e.message ?: ""
            // error=13 Permission denied, error=8 Exec format error = NOT executable
            !msg.contains("error=13") && !msg.contains("error=8") && 
            !msg.contains("Permission denied") && !msg.contains("ENOEXEC")
        }
    }

    // ─── ENSURE PROOT BINARY ──────────────────────────────────────────────────
    // Tries multiple exec-safe locations in priority order.
    private fun ensureProotBinary(): String? {
        // ── Priority 1: nativeLibraryDir (set by Android, always exec-safe) ──
        if (prootBundledBin.exists() && isActuallyExecutable(prootBundledBin)) {
            return null
        }

        // ── Priority 2: codeCacheDir/bin/proot (already extracted & works) ──
        if (prootExtractedBin.exists() && isActuallyExecutable(prootExtractedBin)) {
            return null
        }

        // ── Priority 3: Extract from APK → codeCacheDir (exec-safe on Android) ──
        // codeCacheDir = /data/user/0/com.pyom/code_cache/
        // Android marks this exec-safe for JIT compilation. Never has noexec.
        val extractError = tryExtractProot(prootExtractedBin)
        if (extractError == null && isActuallyExecutable(prootExtractedBin)) {
            prootVersionFile.writeText("extracted-to-codecache")
            return null
        }

        // ── Priority 4: Try other candidate exec-safe paths ──
        val candidates = listOf(
            File(filesDir.parent ?: filesDir.absolutePath, "code_cache/bin/proot"),
            File(applicationInfo.dataDir, "code_cache/bin/proot"),
        )
        for (candidate in candidates) {
            val err = tryExtractProot(candidate)
            if (err == null && isActuallyExecutable(candidate)) {
                // Update prootBin to use this working path dynamically
                prootVersionFile.writeText("alt-path:${candidate.absolutePath}")
                return null
            }
        }

        // All failed — build detailed diagnostic
        val nativeFiles = File(applicationInfo.nativeLibraryDir).listFiles()
            ?.take(8)?.joinToString(", ") { it.name } ?: "none"

        return "FATAL: Cannot execute proot binary on this device.\n\n" +
               "Tried locations:\n" +
               "  1. nativeLibraryDir: ${prootBundledBin.absolutePath}\n" +
               "     → exists=${prootBundledBin.exists()}\n" +
               "  2. codeCacheDir: ${prootExtractedBin.absolutePath}\n" +
               "     → exists=${prootExtractedBin.exists()}, error=${extractError ?: "exec failed"}\n\n" +
               "nativeLibDir contents: [$nativeFiles]\n\n" +
               "SOLUTION: Add the proot ARM64 binary as:\n" +
               "android/app/src/main/jniLibs/arm64-v8a/libproot.so\n" +
               "Download from: https://github.com/termux/proot/releases"
    }

    private fun tryExtractProot(dest: File): String? {
        return try {
            val apkPath = applicationInfo.sourceDir
            ZipFile(apkPath).use { zip ->
                val entry = zip.getEntry("lib/arm64-v8a/libproot.so")
                    ?: return "libproot.so not found in APK"
                dest.parentFile?.mkdirs()
                zip.getInputStream(entry).use { input ->
                    dest.outputStream().use { output -> input.copyTo(output) }
                }
                dest.setExecutable(true, false)
                try {
                    Runtime.getRuntime()
                        .exec(arrayOf("chmod", "755", dest.absolutePath))
                        .waitFor(2, TimeUnit.SECONDS)
                } catch (_: Exception) {}
            }
            null // success
        } catch (e: Exception) {
            e.message
        }
    }

    private fun isEnvironmentInstalled(envId: String): Boolean {
        val envDir = File(envRoot, envId)
        if (!envDir.exists()) return false
        // Check etc/os-release (most reliable indicator)
        if (File(envDir, "etc/os-release").exists()) return true
        // Check shell via robust finder
        return findShellInEnv(envDir) != null
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

            sendProgress("🌐 Checking network…", 0.08)
            checkNetworkOrThrow()

            sendProgress("Downloading $distro rootfs…", 0.10)
            val tarFile = File(extDir, "rootfs_${envId}.tar.gz")
            val sources = rootfsSources[distro] ?: rootfsSources["alpine"]!!
            downloadWithFallback(sources, tarFile, 0.10, 0.60)
            if (isSetupCancelled.get()) { tarFile.delete(); mainHandler.post { result.error("CANCELLED", "Cancelled", null) }; return }

            sendProgress("Extracting rootfs…", 0.62)
            extractTarGz(tarFile, envDir)
            tarFile.delete()
            if (isSetupCancelled.get()) { mainHandler.post { result.error("CANCELLED", "Cancelled", null) }; return }

            sendProgress("🔧 Repairing rootfs symlinks…", 0.73)
            repairRootfsShell(envDir)

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

    // ─── ROOTFS SHELL REPAIR ──────────────────────────────────────────────────
    // Alpine 3.19+ uses merged-usr: /bin is a SYMLINK to usr/bin.
    // Our tar extractor creates the symlink but Java's File.exists() may not
    // follow it properly. This function scans for busybox/sh and creates
    // concrete shell files so proot can always find them.
    private fun repairRootfsShell(envDir: File) {
        // Step 1: Fix /bin if it's a dangling or missing symlink
        val binDir = File(envDir, "bin")
        val usrBinDir = File(envDir, "usr/bin")

        // If /bin doesn't exist or is a broken symlink, create it as real dir
        // or copy from usr/bin
        if (!binDir.exists() && !java.nio.file.Files.isSymbolicLink(binDir.toPath())) {
            if (usrBinDir.exists()) {
                // Create /bin as real directory with essential symlinks
                binDir.mkdirs()
            }
        }

        // Step 2: Find busybox anywhere in the rootfs
        val busyboxLocations = listOf(
            File(envDir, "bin/busybox"),
            File(envDir, "usr/bin/busybox"),
            File(envDir, "sbin/busybox"),
            File(envDir, "usr/sbin/busybox"),
        )
        val busybox = busyboxLocations.firstOrNull { 
            it.exists() || java.nio.file.Files.isSymbolicLink(it.toPath()) 
        }

        // Step 3: Find sh/bash in usr/bin (merged-usr systems)
        val shellInUsrBin = listOf(
            File(envDir, "usr/bin/sh"),
            File(envDir, "usr/bin/bash"),
            File(envDir, "usr/local/bin/sh"),
        ).firstOrNull { it.exists() }

        // Step 4: Ensure /bin/sh exists as a real executable file
        val binSh = File(envDir, "bin/sh")
        if (!binSh.exists()) {
            when {
                shellInUsrBin != null -> {
                    // Copy the actual shell binary to /bin/sh
                    binDir.mkdirs()
                    try {
                        shellInUsrBin.copyTo(binSh, overwrite = true)
                        binSh.setExecutable(true, false)
                    } catch (_: Exception) {}
                }
                busybox != null -> {
                    // Copy busybox to /bin/sh
                    binDir.mkdirs()
                    try {
                        // First copy busybox to bin/ if not already there
                        val binBusybox = File(envDir, "bin/busybox")
                        if (!binBusybox.exists()) {
                            busybox.copyTo(binBusybox, overwrite = true)
                            binBusybox.setExecutable(true, false)
                        }
                        binSh.copyTo(binBusybox, overwrite = false)
                        binBusybox.copyTo(binSh, overwrite = true)
                        binSh.setExecutable(true, false)
                    } catch (_: Exception) {}
                }
                else -> {
                    // Last resort: write a minimal shell wrapper script
                    // This at least lets proot start; real sh will be found inside
                    binDir.mkdirs()
                    // Search recursively for any shell binary
                    val foundShell = envDir.walk()
                        .filter { it.isFile && (it.name == "sh" || it.name == "bash" || it.name == "busybox") }
                        .firstOrNull()
                    if (foundShell != null) {
                        try {
                            foundShell.copyTo(binSh, overwrite = true)
                            binSh.setExecutable(true, false)
                        } catch (_: Exception) {}
                    }
                }
            }
        }

        // Step 5: Ensure /bin/sh is executable
        if (binSh.exists()) binSh.setExecutable(true, false)
        
        // Step 6: Create /usr/bin/env if missing (needed by python3 shebang)
        val usrBinEnv = File(envDir, "usr/bin/env")
        if (!usrBinEnv.exists() && binSh.exists()) {
            usrBinDir.mkdirs()
            // env script fallback
            try {
                usrBinEnv.writeText("#!/bin/sh\nexec \"\$@\"\n")
                usrBinEnv.setExecutable(true, false)
            } catch (_: Exception) {}
        }

        // Step 7: Ensure tmp dir has right permissions
        File(envDir, "tmp").apply { mkdirs(); setWritable(true, false) }
    }

    // ─── FIND SHELL IN ENV ────────────────────────────────────────────────────
    // Robust shell finder — checks real files, symlinks, and merged-usr layouts
    private fun findShellInEnv(envDir: File): String? {
        val candidates = listOf(
            "/bin/bash", "/bin/sh",
            "/usr/bin/bash", "/usr/bin/sh",
            "/usr/local/bin/bash", "/usr/local/bin/sh",
            "/bin/busybox", "/usr/bin/busybox",
        )
        for (shellPath in candidates) {
            val f = File(envDir, shellPath.drop(1))
            // Check real file exists OR is a symlink (might be merged-usr)
            if (f.exists() || java.nio.file.Files.isSymbolicLink(f.toPath())) {
                return shellPath
            }
        }
        // Fallback: scan entire rootfs for any sh/bash binary
        return try {
            val found = envDir.walk()
                .filter { it.isFile && (it.name == "sh" || it.name == "bash") }
                .firstOrNull()
            found?.absolutePath?.removePrefix(envDir.absolutePath)
        } catch (_: Exception) { null }
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
        
        val shell = findShellInEnv(envDir)
            ?: return mapOf("stdout" to "", "exitCode" to -1, "stderr" to 
                "No valid shell found in rootfs.\nDebug info:\n" +
                "- bin/sh exists: ${File(envDir, "bin/sh").exists()}\n" +
                "- bin/sh symlink: ${java.nio.file.Files.isSymbolicLink(File(envDir, "bin/sh").toPath())}\n" +
                "- usr/bin/sh exists: ${File(envDir, "usr/bin/sh").exists()}\n" +
                "- bin/ contents: ${File(envDir, "bin").listFiles()?.take(10)?.map { it.name } ?: "not found"}\n" +
                "Please delete the environment in Settings and reinstall."
            )

        val cmd = listOf(
            prootBin.absolutePath,
            "--kill-on-exit", "-k", "5.4.0", "--link2symlink", "-r", envDir.absolutePath,
            "-w", workingDir, "-b", "/dev", "-b", "/proc", "-b", "/sys",
            "-b", "${extDir.absolutePath}:/data_internal", "-0",
            shell, "-c", command
        )

        val pb = ProcessBuilder(cmd).apply {
            directory(extDir)   // working dir must also be on exec-safe storage
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

    // ─── BIND THREAD TO ACTIVE NETWORK ────────────────────────────────────────
    // This is the ROOT CAUSE FIX: executor threads sometimes lose their
    // network binding on Android, causing DNS to fail even when internet works.
    private fun bindToActiveNetwork() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = cm.activeNetwork
            if (network != null) {
                cm.bindProcessToNetwork(network)
            }
        } catch (e: Exception) {
            // Best-effort — ignore if fails
        }
    }

    // ─── NETWORK CHECK ─────────────────────────────────────────────────────────
    private fun checkNetworkOrThrow() {
        bindToActiveNetwork() // Always bind first!

        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork
        val capabilities = if (network != null) cm.getNetworkCapabilities(network) else null

        val hasInternet = capabilities != null && (
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        )

        if (!hasInternet) {
            throw Exception(
                "❌ No active internet connection detected.\n\n" +
                "Please check:\n" +
                "  • WiFi or mobile data is ON\n" +
                "  • Airplane mode is OFF\n" +
                "  • App has network permission in Settings\n"
            )
        }
    }

    // ─── MULTI-MIRROR DOWNLOAD ─────────────────────────────────────────────────
    private fun downloadWithFallback(
        mirrors: List<String>,
        dest: File,
        progressStart: Double,
        progressEnd: Double,
    ) {
        bindToActiveNetwork()
        var lastException: Exception? = null

        mirrors.forEachIndexed { index, urlStr ->
            if (isSetupCancelled.get()) throw Exception("Download cancelled")
            try {
                sendProgress("📥 Trying mirror ${index + 1}/${mirrors.size}…", progressStart + 0.01)
                downloadWithProgress(urlStr, dest, progressStart, progressEnd)
                return // Success
            } catch (e: Exception) {
                lastException = e
                if (e.message?.contains("cancelled") == true) throw e
                val reason = when {
                    e.message?.contains("resolve host") == true ||
                    e.message?.contains("UnknownHost") == true -> "DNS failed"
                    e.message?.contains("timeout") == true ||
                    e.message?.contains("timed out") == true -> "Timeout"
                    e.message?.contains("HTTP 403") == true ||
                    e.message?.contains("HTTP 404") == true -> "Not found"
                    e.message?.contains("SSL") == true -> "SSL error"
                    else -> "Failed: ${e.message?.take(40)}"
                }
                sendProgress("⚠️ Mirror ${index + 1} failed ($reason)…", progressStart + 0.02)
                dest.takeIf { it.exists() }?.delete()
                // Re-bind before next attempt
                bindToActiveNetwork()
            }
        }

        throw Exception(
            "❌ All ${mirrors.size} mirrors failed.\nLast error: ${lastException?.message}\n\n" +
            "Please check your internet connection and try again."
        )
    }

    // ─── OKHTTP DOWNLOAD ───────────────────────────────────────────────────────
    private fun downloadWithProgress(
        urlStr: String,
        dest: File,
        progressStart: Double,
        progressEnd: Double,
    ) {
        bindToActiveNetwork() // Bind before every individual attempt

        val request = Request.Builder()
            .url(urlStr)
            .header("User-Agent", "Pyom-IDE/1.0 Android")
            .build()

        okHttpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw Exception("HTTP ${response.code} from server")
            }

            val body = response.body ?: throw Exception("Empty response body")
            val total = body.contentLength() // -1 if unknown

            var downloaded = 0L
            var lastUpdateMs = System.currentTimeMillis()

            body.byteStream().use { input ->
                FileOutputStream(dest).use { output ->
                    val buf = ByteArray(65536) // 64KB buffer
                    var n: Int
                    while (input.read(buf).also { n = it } != -1) {
                        if (isSetupCancelled.get()) throw Exception("Download cancelled")
                        output.write(buf, 0, n)
                        downloaded += n

                        val now = System.currentTimeMillis()
                        if (now - lastUpdateMs > 900) {
                            lastUpdateMs = now
                            val ratio = if (total > 0) downloaded.toDouble() / total else 0.4
                            val p = progressStart + ratio * (progressEnd - progressStart)
                            val dlMB = (downloaded / 1_048_576.0).toInt()
                            val totalStr = if (total > 0) "/ ${(total / 1_048_576.0).toInt()}MB" else ""
                            sendProgress("📥 ${dlMB}MB $totalStr", p.coerceIn(progressStart, progressEnd))
                        }
                    }
                }
            }

            if (dest.length() < 512) {
                dest.delete()
                throw Exception("Downloaded file too small (${dest.length()} bytes) — server may have returned an error page")
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
