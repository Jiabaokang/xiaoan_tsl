package com.jbk.xiaoants

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.system.ErrnoException
import android.system.OsConstants
import com.google.mlkit.common.MlKitException
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.net.ConnectException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.Executor
import java.util.Locale
import javax.net.ssl.SSLException

/** 在引擎生命周期内管理 ML Kit 模型下载、网络等待和 Flutter 异步协议。 */
class ModelDownloadPlugin(
    private val modelManagerProvider: () -> RemoteModelManager = { RemoteModelManager.getInstance() }
) : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "offline_language_model_downloads"
        private const val NOTIFICATION_PERMISSION_REQUEST = 7318
        private const val PREFERENCES_NAME = "model_download_notifications"
        private const val PERMISSION_PROMPTED_KEY = "notification_permission_prompted"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val modelManager by lazy(modelManagerProvider)
    // 通道调用、网络通知与 SDK 回调统一在主线程修改任务，避免重复启动和重复回复。
    private val pending = mutableMapOf<String, PendingDownload>()
    private val networks = mutableMapOf<Network, NetworkCapabilities>()
    private val blockedNetworks = mutableSetOf<Network>()
    private var attached = false
    private var connectivity: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkError: Exception? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var appContext: Context? = null
    private var notificationManager: NotificationManager? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var notificationPermissionRequested = false
    private val mainExecutor = Executor { action ->
        if (attached) {
            if (Looper.myLooper() == Looper.getMainLooper()) action.run()
            else mainHandler.post { if (attached) action.run() }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = true
        networkError = null
        appContext = binding.applicationContext
        notificationManager = binding.applicationContext
            .getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        createNotificationChannel(binding.applicationContext)
        methodChannel = MethodChannel(binding.binaryMessenger, "xiaoan_tsl/model_download").also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, "xiaoan_tsl/model_download_events").also {
            it.setStreamHandler(this)
        }
        observeNetworks(binding.applicationContext)
    }

    /** 只在引擎解绑时释放资源；Activity 重建不改变 SDK 下载生命周期。 */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        val callback = networkCallback
        networkCallback = null
        if (callback != null) {
            try {
                connectivity?.unregisterNetworkCallback(callback)
            } catch (_: RuntimeException) {
                // 系统可能已撤销回调，仍须继续结束所有 Flutter 调用。
            }
        }
        connectivity = null
        networks.clear()
        blockedNetworks.clear()
        mainHandler.removeCallbacksAndMessages(null)
        val downloads = pending.values.toList()
        pending.clear()
        downloads.forEach { task ->
            cancelNotification(task.model)
            task.results.forEach {
                it.error("unavailable", "Download bridge detached from engine", mapOf(
                    "model" to task.model, "reason" to "engineDetached"
                ))
            }
            task.results.clear()
        }
        // RemoteModelManager 没有公开的取消接口；已启动的 SDK 任务可能继续写入模型存储。
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            pending.values.forEach(::updateNotification)
        }
        return true
    }

    /** Android 13 及以上首次下载时申请提醒权限；拒绝权限不影响模型下载。 */
    private fun requestNotificationPermissionIfNeeded() {
        val context = appContext ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        try {
            if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            ) return
            val activity = activityBinding?.activity ?: return
            val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            if (notificationPermissionRequested || preferences.getBoolean(PERMISSION_PROMPTED_KEY, false)) return
            notificationPermissionRequested = true
            preferences.edit().putBoolean(PERMISSION_PROMPTED_KEY, true).apply()
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
        } catch (_: SecurityException) {
            // 权限申请失败时继续执行下载。
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "download" && call.method != "allowMobileData") {
            result.notImplemented()
            return
        }
        if (!attached) {
            result.error("unavailable", "Download bridge is detached", mapOf("reason" to "engineDetached"))
            return
        }
        val args = call.arguments as? Map<*, *>
        val model = args?.get("model") as? String
        if (model == null || model !in TranslateLanguage.getAllLanguages()) {
            result.error("unavailable", "Unsupported translation model", mapOf("reason" to "invalidModel"))
            return
        }
        if (call.method == "allowMobileData") {
            allowMobileData(model, result)
            return
        }
        val wifiOnly = args["wifiOnly"] as? Boolean
        if (wifiOnly == null) {
            result.error("unavailable", "wifiOnly must be a boolean", mapOf(
                "model" to model, "reason" to "invalidArguments"
            ))
            return
        }
        val existing = pending[model]
        if (existing != null) {
            // 重复请求只加入等待；改变已确认的策略必须走 allowMobileData。
            existing.results.add(result)
            emit(existing, force = true)
            return
        }
        try {
            val task = PendingDownload(model, TranslateRemoteModel.Builder(model).build(), wifiOnly, result)
            pending[model] = task
            refresh(task)
            // 本地已有模型时离线也应成功，不必等待网络或触发新的下载。
            modelManager.isModelDownloaded(task.remoteModel).addOnCompleteListener(mainExecutor) { check ->
                if (!isCurrent(task)) return@addOnCompleteListener
                when {
                    check.isSuccessful && check.result == true -> succeed(task)
                    check.isSuccessful -> {
                        task.checkingReady = false
                        val failure = networkError
                        if (failure != null) {
                            fail(task, failure)
                        } else {
                            requestNotificationPermissionIfNeeded()
                            refresh(task)
                        }
                    }
                    else -> fail(task, check.exception ?: cancelled())
                }
            }
        } catch (error: Exception) {
            val task = pending[model]
            if (task != null) fail(task, error) else replyError(result, model, error)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        pending.values.forEach { emit(it, force = true) }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /** 仅允许尚未交给 SDK、当前正在等待 Wi-Fi 的任务放宽策略。 */
    private fun allowMobileData(model: String, result: MethodChannel.Result) {
        val task = pending[model]
        if (task == null || task.started || task.phase != "waitingWifi") {
            result.error("unsupported", "Only an unstarted waitingWifi task can use mobile data", mapOf(
                "model" to model, "reason" to "policyChangeUnsupported"
            ))
            return
        }
        task.wifiOnly = false
        refresh(task)
        result.success(null)
    }

    /** 监听所有可提供互联网的网络；仅经系统验证且未被阻止的网络可启动 SDK。 */
    private fun observeNetworks(context: Context) {
        try {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivity = manager
            // 将系统网络变化转发到引擎主线程，旧注册的延迟通知不得影响新任务。
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    // API 26 起系统保证紧随其后通知能力；旧系统补读新出现的网络。
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        dispatch {
                            manager.getNetworkCapabilities(network)?.let { networks[network] = it }
                            refreshAll()
                        }
                    }
                }

                override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                    dispatch {
                        networks[network] = capabilities
                        refreshAll()
                    }
                }

                override fun onLost(network: Network) {
                    dispatch {
                        networks.remove(network)
                        blockedNetworks.remove(network)
                        refreshAll()
                    }
                }

                override fun onBlockedStatusChanged(network: Network, blocked: Boolean) {
                    dispatch {
                        if (blocked) blockedNetworks.add(network) else blockedNetworks.remove(network)
                        refreshAll()
                    }
                }

                private fun dispatch(action: () -> Unit) {
                    mainExecutor.execute { if (networkCallback === this) action() }
                }
            }
            manager.registerNetworkCallback(
                NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    .build(),
                callback
            )
            networkCallback = callback
            // 回调注册后读取初始快照，后续能力变化与丢失以回调为准。
            @Suppress("DEPRECATION") // 首次回调到达前需要兼容 API 24 的现有网络快照。
            val initialNetworks = manager.allNetworks
            initialNetworks.forEach { network ->
                manager.getNetworkCapabilities(network)?.let { networks[network] = it }
            }
        } catch (error: Exception) {
            networkError = error
        }
    }

    private fun refreshAll() = pending.values.toList().forEach { refresh(it) }

    /** started 一旦置位便保持策略不变，断网只更新状态，不重新调用 download。 */
    private fun refresh(task: PendingDownload) {
        if (!isCurrent(task)) return
        val usable = networks.filter { (network, capabilities) ->
            network !in blockedNetworks &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) &&
                (Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED))
        }.values
        val hasWifi = usable.any { it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) }
        task.phase = when {
            usable.isEmpty() -> "waitingNetwork"
            task.wifiOnly && !hasWifi -> "waitingWifi"
            else -> "downloading"
        }
        emit(task)
        if (task.phase == "downloading" && !task.started && !task.checkingReady && networkError == null) {
            start(task)
        }
    }

    private fun emit(task: PendingDownload, force: Boolean = false) {
        val event = mapOf(
            "model" to task.model,
            "phase" to task.phase,
            "canUseMobile" to (!task.started && task.wifiOnly && task.phase == "waitingWifi")
        )
        if (force || event != task.lastEvent) {
            task.lastEvent = event
            eventSink?.success(event)
            updateNotification(task)
        }
    }

    /** SDK 不提供可靠的字节进度，downloading 同时涵盖准备和传输阶段。 */
    private fun start(task: PendingDownload) {
        task.started = true
        emit(task)
        try {
            val conditions = DownloadConditions.Builder().apply { if (task.wifiOnly) requireWifi() }.build()
            modelManager.download(task.remoteModel, conditions).addOnCompleteListener(mainExecutor) { download ->
                if (!isCurrent(task)) return@addOnCompleteListener
                if (!download.isSuccessful) {
                    fail(task, download.exception ?: cancelled())
                    return@addOnCompleteListener
                }
                verifyReady(task)
            }
        } catch (error: Exception) {
            fail(task, error)
        }
    }

    private fun verifyReady(task: PendingDownload) {
        try {
            modelManager.isModelDownloaded(task.remoteModel).addOnCompleteListener(mainExecutor) { check ->
                if (!isCurrent(task)) return@addOnCompleteListener
                when {
                    check.isSuccessful && check.result == true -> succeed(task)
                    !check.isSuccessful -> fail(task, check.exception ?: cancelled())
                    else -> fail(task, MlKitException("Downloaded model is not ready", MlKitException.UNAVAILABLE))
                }
            }
        } catch (error: Exception) {
            fail(task, error)
        }
    }

    private fun isCurrent(task: PendingDownload) = attached && pending[task.model] === task

    private fun succeed(task: PendingDownload) {
        if (!isCurrent(task)) return
        updateNotification(task, phase = "completed")
        pending.remove(task.model)
        task.results.forEach { it.success("success") }
        task.results.clear()
    }

    private fun fail(task: PendingDownload, error: Exception) {
        if (!isCurrent(task)) return
        updateNotification(task, phase = "failed", error = error)
        pending.remove(task.model)
        task.results.forEach { replyError(it, task.model, error) }
        task.results.clear()
    }

    /** 保留原始 SDK 错误码及因果链，避免把所有下载失败误报成网络问题。 */
    private fun replyError(result: MethodChannel.Result, model: String, error: Exception) {
        val failure = classifyFailure(error)
        result.error(failure.category, error.message ?: "Model download failed", mapOf(
            "model" to model,
            "sdkCode" to failure.sdkCode,
            "nativeType" to error.javaClass.name,
            "causes" to failure.causes.map { cause -> mapOf(
                "type" to cause.javaClass.name,
                "message" to cause.message,
                "sdkCode" to (cause as? MlKitException)?.errorCode,
                "errno" to (cause as? ErrnoException)?.errno
            ) }
        ))
    }

    /** 通知与 Flutter 错误共用同一分类，避免显示互相矛盾的原因。 */
    private fun classifyFailure(error: Exception): DownloadFailure {
        val causes = mutableListOf<Throwable>()
        var current: Throwable? = error
        while (current != null && causes.none { it === current }) {
            causes.add(current)
            current = current.cause
        }
        val sdkCode = causes.filterIsInstance<MlKitException>().firstOrNull()?.errorCode
        val category = when (sdkCode) {
            MlKitException.NETWORK_ISSUE, MlKitException.DEADLINE_EXCEEDED -> "network"
            MlKitException.NOT_ENOUGH_SPACE -> "storage"
            MlKitException.MODEL_HASH_MISMATCH, MlKitException.DATA_LOSS -> "integrity"
            MlKitException.UNAVAILABLE, MlKitException.NOT_FOUND, MlKitException.UNIMPLEMENTED,
            MlKitException.UNSUPPORTED, MlKitException.MODEL_INCOMPATIBLE_WITH_TFLITE -> "unavailable"
            else -> when {
                causes.any { it is ErrnoException && (it.errno == OsConstants.ENOSPC || it.errno == OsConstants.EDQUOT) } -> "storage"
                causes.any { it is SecurityException } -> "unavailable"
                causes.any { it is UnknownHostException || it is SocketTimeoutException || it is ConnectException ||
                    it is SocketException || it is SSLException } -> "network"
                else -> "unknown"
            }
        }
        return DownloadFailure(category, sdkCode, causes)
    }

    /** 初始化低打扰通知渠道；通知不可用时静默跳过。 */
    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager ?: return
        try {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                context.getString(R.string.model_download_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = context.getString(R.string.model_download_channel_description)
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        } catch (_: SecurityException) {
            // 权限问题不影响下载。
        }
    }

    /** 同一语言复用通知 ID；下载阶段使用不定进度，避免伪造百分比。 */
    private fun updateNotification(task: PendingDownload, phase: String = task.phase, error: Exception? = null) {
        val context = appContext ?: return
        val manager = notificationManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return
            if (!manager.areNotificationsEnabled()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE
            ) return

            val language = Locale.forLanguageTag(task.model).getDisplayLanguage(Locale.getDefault())
                .ifBlank { task.model.uppercase(Locale.ROOT) }
            val text = when (phase) {
                "waitingWifi" -> context.getString(R.string.model_download_waiting_wifi)
                "waitingNetwork" -> context.getString(R.string.model_download_waiting_network)
                "downloading" -> context.getString(R.string.model_download_downloading)
                "completed" -> context.getString(R.string.model_download_completed)
                "failed" -> failureNotificationText(context, error)
                else -> return
            }
            val ongoing = phase == "waitingWifi" || phase == "waitingNetwork" || phase == "downloading"
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("xiaoants://app/offline-models")
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val click = PendingIntent.getActivity(
                context,
                notificationId(task.model),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
            } else {
                Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(R.drawable.ic_notification_download)
                .setContentTitle(context.getString(R.string.model_download_title, language))
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(click)
                .setOnlyAlertOnce(true)
                .setOngoing(ongoing)
                .setAutoCancel(!ongoing)
                .setCategory(if (ongoing) Notification.CATEGORY_PROGRESS else Notification.CATEGORY_STATUS)
                .apply { if (phase == "downloading") setProgress(0, 0, true) }
                .build()
            manager.notify(notificationId(task.model), notification)
        } catch (_: SecurityException) {
            // 系统撤销通知权限时静默失败，模型下载仍继续。
        }
    }

    /** 通知仅展示可操作的失败原因，不暴露 SDK 内部错误。 */
    private fun failureNotificationText(context: Context, error: Exception?): String {
        val message = when (error?.let { classifyFailure(it).category }) {
            "network" -> R.string.model_download_failed_network
            "storage" -> R.string.model_download_failed_storage
            "integrity" -> R.string.model_download_failed_integrity
            "unavailable" -> R.string.model_download_failed_unavailable
            else -> R.string.model_download_failed_unknown
        }
        return context.getString(message)
    }

    /** 引擎销毁时移除仍显示进行中的模型通知。 */
    private fun cancelNotification(model: String) {
        try {
            notificationManager?.cancel(notificationId(model))
        } catch (_: SecurityException) {
            // 通知已被系统禁用时无需处理。
        }
    }

    /** 将语言代码映射为稳定的正整数通知 ID。 */
    private fun notificationId(model: String) = ("model_download_$model").hashCode() and Int.MAX_VALUE

    private fun cancelled() = MlKitException("Model download task was cancelled", MlKitException.CANCELLED)

    /** 保留错误分类与完整因果链，供通知文案和 Flutter 错误详情共用。 */
    private data class DownloadFailure(
        val category: String,
        val sdkCode: Int?,
        val causes: List<Throwable>
    )

    /** 合并同一语言的调用，记录提交给 SDK 前可变、提交后固定的网络策略。 */
    private class PendingDownload(
        val model: String,
        val remoteModel: TranslateRemoteModel,
        var wifiOnly: Boolean,
        result: MethodChannel.Result
    ) {
        val results = mutableListOf(result)
        var checkingReady = true
        var started = false
        var phase = "waitingNetwork"
        var lastEvent: Map<String, Any>? = null
    }
}
