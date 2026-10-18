package com.jbk.xiaoants

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** 承载 Flutter 页面，并为每个引擎注册一次模型下载桥接。 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(ModelDownloadPlugin::class.java)) {
            flutterEngine.plugins.add(ModelDownloadPlugin())
        }
    }
}
