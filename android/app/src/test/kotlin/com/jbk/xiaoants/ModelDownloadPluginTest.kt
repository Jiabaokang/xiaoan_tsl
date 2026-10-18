package com.jbk.xiaoants

import android.Manifest
import android.content.Context
import android.content.ContextWrapper
import android.content.res.Resources
import android.app.Notification
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Looper
import android.net.Uri
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.MlKitException
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModel
import com.google.mlkit.common.model.RemoteModelManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowNetwork
import org.robolectric.shadows.ShadowNetworkCapabilities
import java.net.UnknownHostException
import java.util.Locale

/** 验证原生下载桥接的网络策略、异步完成、错误及引擎资源释放。 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], manifest = Config.NONE)
class ModelDownloadPluginTest {
    private lateinit var plugin: ModelDownloadPlugin
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private lateinit var connectivity: ConnectivityManager
    private lateinit var callback: ConnectivityManager.NetworkCallback
    private lateinit var manager: RemoteModelManager
    private lateinit var notificationManager: NotificationManager
    private lateinit var appContext: Context
    private lateinit var pluginContext: NotificationTestContext
    private lateinit var transfer: TaskCompletionSource<Void>
    private val events = RecordingEvents()
    private val network = ShadowNetwork.newInstance(1)
    private val conditions = mutableListOf<DownloadConditions>()
    private var ready = false

    @Before
    @Suppress("DEPRECATION")
    fun setUp() {
        connectivity = mock(ConnectivityManager::class.java)
        `when`(connectivity.allNetworks).thenReturn(emptyArray())
        doAnswer {
            callback = it.getArgument(1)
            null
        }.`when`(connectivity).registerNetworkCallback(
            any(NetworkRequest::class.java), any(ConnectivityManager.NetworkCallback::class.java)
        )
        appContext = RuntimeEnvironment.getApplication()
        notificationManager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancelAll()
        pluginContext = NotificationTestContext(appContext)
        binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.applicationContext).thenReturn(pluginContext)
        `when`(binding.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))
        manager = mock(RemoteModelManager::class.java)
        doAnswer { Tasks.forResult(ready) }.`when`(manager)
            .isModelDownloaded(any(RemoteModel::class.java))
        transfer = TaskCompletionSource()
        doAnswer {
            conditions.add(it.getArgument(1))
            transfer.task
        }.`when`(manager).download(any(RemoteModel::class.java), any(DownloadConditions::class.java))
        plugin = ModelDownloadPlugin { manager }
        plugin.onAttachedToEngine(binding)
        plugin.onListen(null, events)
    }

    @After
    fun tearDown() {
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun offlineWaitsWithoutStartingSdkThenWifiCompletesAllJoinedCalls() {
        val first = download()
        val second = download(wifiOnly = false)
        assertEquals(event("waitingNetwork", false), events.last())
        assertTrue(conditions.isEmpty())
        assertEquals(0, first.completions)
        connect(wifi = true)
        assertEquals(event("downloading", false), events.last())
        assertEquals(1, conditions.size)
        assertTrue(conditions.single().isWifiRequired)
        assertEquals(0, second.completions)
        ready = true
        transfer.setResult(null)
        drain()
        assertEquals("success", first.value)
        assertEquals("success", second.value)
        assertEquals(1, first.completions)
    }

    @Test
    fun onlyExplicitMobileConsentRelaxesAnUnstartedWifiWait() {
        connect(wifi = false)
        val pending = download()
        assertEquals(event("waitingWifi", true), events.last())
        assertTrue(conditions.isEmpty())
        val consent = call("allowMobileData", mapOf("model" to "fr"))
        assertEquals(1, consent.completions)
        assertNull(consent.code)
        assertNull(consent.value)
        assertFalse(conditions.single().isWifiRequired)
        assertEquals(event("downloading", false), events.last())
        assertEquals(0, pending.completions)
    }

    @Test
    fun startedWifiTaskCannotBeRelaxedAfterWifiDisappears() {
        connect(wifi = true)
        download()
        callback.onLost(network)
        drain()
        assertEquals(event("waitingNetwork", false), events.last())
        connect(wifi = false)
        assertEquals(event("waitingWifi", false), events.last())
        assertEquals("unsupported", call("allowMobileData", mapOf("model" to "fr")).code)
        connect(wifi = true)
        assertEquals(1, conditions.size)
    }

    @Test
    fun noPendingTaskAndOfflineTaskRejectPolicyChange() {
        assertEquals("unsupported", call("allowMobileData", mapOf("model" to "fr")).code)
        download()
        assertEquals("unsupported", call("allowMobileData", mapOf("model" to "fr")).code)
        assertTrue(conditions.isEmpty())
    }

    @Test
    fun captiveOrBlockedWifiDoesNotStartSdk() {
        connect(wifi = true, validated = false)
        download()
        assertEquals(event("waitingNetwork", false), events.last())
        callback.onBlockedStatusChanged(network, true)
        connect(wifi = true)
        assertTrue(conditions.isEmpty())
        callback.onBlockedStatusChanged(network, false)
        drain()
        assertEquals(1, conditions.size)
    }

    @Test
    fun mobileAllowedTaskStartsOnValidatedCellular() {
        connect(wifi = false)
        download(wifiOnly = false)
        assertFalse(conditions.single().isWifiRequired)
    }

    @Test
    fun suspendedWifiWaitsUntilUsableAgain() {
        val suspended = capabilities(wifi = true)
        shadowOf(suspended).removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED)
        callback.onCapabilitiesChanged(network, suspended)
        drain()
        download()
        assertEquals(event("waitingNetwork", false), events.last())
        assertTrue(conditions.isEmpty())
        connect(wifi = true)
        assertEquals(1, conditions.size)
    }

    @Test
    fun connectivityIsRecheckedAfterAsynchronousLocalModelQuery() {
        val preflight = TaskCompletionSource<Boolean>()
        doReturn(preflight.task).`when`(manager).isModelDownloaded(any(RemoteModel::class.java))
        connect(wifi = true)
        val pending = download()
        callback.onLost(network)
        drain()
        preflight.setResult(false)
        drain()
        assertTrue(conditions.isEmpty())
        assertEquals(0, pending.completions)
        connect(wifi = true)
        assertEquals(1, conditions.size)
    }

    @Test
    fun differentModelsHaveIndependentCompletion() {
        connect(wifi = true)
        val frenchTransfer = transfer
        val french = download()
        transfer = TaskCompletionSource()
        val german = call("download", mapOf("model" to "de", "wifiOnly" to true))
        assertEquals(2, conditions.size)
        frenchTransfer.setException(MlKitException("offline", MlKitException.NETWORK_ISSUE))
        drain()
        assertEquals("network", french.code)
        assertEquals(0, german.completions)
        ready = true
        transfer.setResult(null)
        drain()
        assertEquals("success", german.value)
    }

    @Test
    fun networkRegistrationFailureReturnsErrorInsteadOfHanging() {
        plugin.onDetachedFromEngine(binding)
        doThrow(SecurityException("permission denied")).`when`(connectivity).registerNetworkCallback(
            any(NetworkRequest::class.java), any(ConnectivityManager.NetworkCallback::class.java)
        )
        plugin.onAttachedToEngine(binding)
        val result = download()
        assertEquals("unavailable", result.code)
        assertEquals(1, result.completions)
        assertTrue(conditions.isEmpty())
    }

    @Test
    fun locallyReadyModelSucceedsEvenOffline() {
        ready = true
        assertEquals("success", download().value)
        assertTrue(conditions.isEmpty())
    }

    @Test
    fun sdkCompletionMustStillConfirmModelReady() {
        connect(wifi = true)
        val pending = download()
        transfer.setResult(null)
        drain()
        assertEquals("unavailable", pending.code)
        assertNull(pending.value)
    }

    @Test
    fun notificationNamesTheLanguageAndTracksWifiWaitAndDownload() {
        connect(wifi = false)
        download()

        var notification = latestNotification()
        assertEquals(
            NotificationManager.IMPORTANCE_DEFAULT,
            notificationManager.getNotificationChannel("offline_language_model_downloads")?.importance
        )
        assertTrue(notification.extras.getCharSequence(Notification.EXTRA_TITLE).toString()
            .contains("French"))
        assertEquals(pluginContext.getString(R.string.model_download_waiting_wifi),
            notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertNotEquals(0, notification.flags and Notification.FLAG_ONGOING_EVENT)

        connect(wifi = true)
        notification = latestNotification()
        assertEquals(pluginContext.getString(R.string.model_download_downloading),
            notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE))
    }

    @Test
    fun notificationReportsCompletionAndCanOpenOfflineModels() {
        connect(wifi = true)
        val pending = download()
        ready = true
        transfer.setResult(null)
        drain()

        assertEquals("success", pending.value)
        val notification = latestNotification()
        assertEquals(pluginContext.getString(R.string.model_download_completed),
            notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(0, notification.flags and Notification.FLAG_ONGOING_EVENT)
        val intent = shadowOf(notification.contentIntent).savedIntent
        assertEquals(Uri.parse("xiaoants://app/offline-models"), intent.data)
        assertEquals("android.intent.action.VIEW", intent.action)
    }

    @Test
    fun notificationExplainsNetworkFailureWithoutBlockingTheDownloadResult() {
        connect(wifi = true)
        val pending = download()
        transfer.setException(MlKitException("offline", MlKitException.NETWORK_ISSUE))
        drain()

        assertEquals("network", pending.code)
        assertEquals(pluginContext.getString(R.string.model_download_failed_network),
            latestNotification().extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(0, latestNotification().flags and Notification.FLAG_ONGOING_EVENT)
    }

    @Test
    @Config(sdk = [33])
    fun denyingNotificationPermissionDoesNotBlockTheModelDownload() {
        pluginContext.denyNotifications = true
        connect(wifi = true)
        val pending = download()

        assertEquals(1, conditions.size)
        assertTrue(shadowOf(notificationManager).allNotifications.isEmpty())
        ready = true
        transfer.setResult(null)
        drain()
        assertEquals("success", pending.value)
    }

    @Test
    fun sdkErrorsKeepCategoryCodeAndOriginalCause() {
        val cases = mapOf(
            MlKitException.NETWORK_ISSUE to "network",
            MlKitException.NOT_ENOUGH_SPACE to "storage",
            MlKitException.MODEL_HASH_MISMATCH to "integrity",
            MlKitException.MODEL_INCOMPATIBLE_WITH_TFLITE to "unavailable",
            MlKitException.INTERNAL to "unknown"
        )
        connect(wifi = true)
        for ((sdkCode, category) in cases) {
            transfer = TaskCompletionSource()
            val pending = download()
            transfer.setException(MlKitException("original SDK failure", sdkCode, IllegalStateException("cause")))
            drain()
            assertEquals(category, pending.code)
            val details = pending.details as Map<*, *>
            assertEquals(sdkCode, details["sdkCode"])
            assertTrue(details["causes"].toString().contains("cause"))
        }
    }

    @Test
    fun wrappedSdkAndNetworkErrorsAreClassified() {
        connect(wifi = true)
        var pending = download()
        transfer.setException(IllegalStateException("wrapper", MlKitException("space", MlKitException.NOT_ENOUGH_SPACE)))
        drain()
        assertEquals("storage", pending.code)
        assertEquals(MlKitException.NOT_ENOUGH_SPACE, (pending.details as Map<*, *>)["sdkCode"])
        transfer = TaskCompletionSource()
        pending = download()
        transfer.setException(UnknownHostException("dns"))
        drain()
        assertEquals("network", pending.code)
    }

    @Test
    fun invalidArgumentsNeverEscapeOrStartSdk() {
        for (args in listOf(null, "fr", mapOf("model" to 7), mapOf("model" to "xx", "wifiOnly" to true),
            mapOf("model" to "fr", "wifiOnly" to "true"), mapOf("model" to "fr"))) {
            assertEquals("unavailable", call("download", args).code)
        }
        assertTrue(conditions.isEmpty())
    }

    @Test
    fun reListeningReplaysPendingStatusAndDetachResolvesEveryCallOnce() {
        val first = download()
        val second = download()
        plugin.onCancel(null)
        val replay = RecordingEvents()
        plugin.onListen(null, replay)
        assertEquals(event("waitingNetwork", false), replay.last())
        plugin.onDetachedFromEngine(binding)
        verify(connectivity).unregisterNetworkCallback(callback)
        verify(binding.binaryMessenger).setMessageHandler("xiaoan_tsl/model_download", null)
        verify(binding.binaryMessenger).setMessageHandler("xiaoan_tsl/model_download_events", null)
        assertEquals("unavailable", first.code)
        assertEquals("unavailable", second.code)
        callback.onCapabilitiesChanged(network, capabilities(wifi = true))
        drain()
        assertTrue(conditions.isEmpty())
        assertEquals(1, first.completions)
        assertEquals(1, second.completions)
    }

    @Test
    fun lateSdkCompletionAfterDetachDoesNotReplyTwice() {
        connect(wifi = true)
        val pending = download()
        plugin.onDetachedFromEngine(binding)
        ready = true
        transfer.setResult(null)
        drain()
        assertEquals("unavailable", pending.code)
        assertEquals(1, pending.completions)
    }

    private fun download(wifiOnly: Boolean = true) =
        call("download", mapOf("model" to "fr", "wifiOnly" to wifiOnly))

    private fun call(method: String, args: Any?): RecordingResult {
        val result = RecordingResult()
        plugin.onMethodCall(MethodCall(method, args), result)
        drain()
        return result
    }

    private fun connect(wifi: Boolean, validated: Boolean = true) {
        callback.onCapabilitiesChanged(network, capabilities(wifi, validated))
        drain()
    }

    private fun capabilities(wifi: Boolean, validated: Boolean = true): NetworkCapabilities {
        val capabilities = ShadowNetworkCapabilities.newInstance()
        shadowOf(capabilities).apply {
            addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED)
            addTransportType(if (wifi) NetworkCapabilities.TRANSPORT_WIFI else NetworkCapabilities.TRANSPORT_CELLULAR)
            if (validated) addCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        }
        return capabilities
    }

    private fun drain() = shadowOf(Looper.getMainLooper()).idle()

    private fun latestNotification(): Notification =
        shadowOf(notificationManager).allNotifications.single()

    /** 在 manifest=NONE 的测试环境中提供通知文案，同时保留真实通知与 PendingIntent 行为。 */
    private inner class NotificationTestContext(base: Context) : ContextWrapper(base) {
        var denyNotifications = false
        private val notificationResources = object : Resources(
            base.assets, base.resources.displayMetrics, base.resources.configuration
        ) {
            override fun getString(id: Int): String = when (id) {
                R.string.model_download_channel_name -> "Offline language downloads"
                R.string.model_download_channel_description -> "Model download status"
                R.string.model_download_waiting_wifi -> "Waiting for Wi-Fi"
                R.string.model_download_waiting_network -> "Waiting for a network connection"
                R.string.model_download_downloading -> "Downloading…"
                R.string.model_download_completed -> "Download complete and ready to use offline"
                R.string.model_download_failed_network -> "Network connection failed. Check your connection and retry."
                R.string.model_download_failed_storage -> "Not enough storage space. Free up space and retry."
                R.string.model_download_failed_integrity -> "The downloaded file could not be verified. Please retry."
                R.string.model_download_failed_unavailable -> "This language model is temporarily unavailable. Please retry later."
                R.string.model_download_failed_unknown -> "Download failed. Check your connection and available storage, then retry."
                else -> throw Resources.NotFoundException("Unknown test string $id")
            }

            override fun getString(id: Int, vararg formatArgs: Any?): String = when (id) {
                R.string.model_download_title -> "Xiaoan Translator · ${formatArgs.first()} offline language pack"
                else -> String.format(Locale.ROOT, getString(id), *formatArgs)
            }
        }

        override fun getResources(): Resources = notificationResources

        override fun getSystemService(name: String): Any? =
            if (name == Context.CONNECTIVITY_SERVICE) connectivity else super.getSystemService(name)

        override fun checkSelfPermission(permission: String): Int =
            if (denyNotifications && permission == Manifest.permission.POST_NOTIFICATIONS) {
                PackageManager.PERMISSION_DENIED
            } else {
                super.checkSelfPermission(permission)
            }

    }

    private fun event(phase: String, mobile: Boolean) =
        mapOf("model" to "fr", "phase" to phase, "canUseMobile" to mobile)

    /** 收集协议返回值，发现提前成功或重复回复。 */
    private class RecordingResult : MethodChannel.Result {
        var value: Any? = null
        var code: String? = null
        var details: Any? = null
        var completions = 0
        override fun success(result: Any?) { value = result; completions++ }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            code = errorCode; details = errorDetails; completions++
        }
        override fun notImplemented() { code = "notImplemented"; completions++ }
    }

    /** 保存真实桥接事件以检查对 Flutter 暴露的状态。 */
    private class RecordingEvents : EventChannel.EventSink {
        private val values = mutableListOf<Any?>()
        override fun success(event: Any?) { values.add(event) }
        override fun error(code: String, message: String?, details: Any?) { fail(message) }
        override fun endOfStream() = Unit
        fun last(): Any? = values.lastOrNull()
    }
}
