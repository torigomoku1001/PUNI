package com.puni.app.puni_project

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
	companion object {
		private const val HEALTH_CONNECT_CHANNEL = "puni/health_connect"
		private const val HEALTH_CONNECT_PACKAGE = "com.google.android.apps.healthdata"
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			HEALTH_CONNECT_CHANNEL,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"openHealthConnectApp" -> openHealthConnectApp(result)
				else -> result.notImplemented()
			}
		}
	}

	private fun openHealthConnectApp(result: MethodChannel.Result) {
		try {
			val launchIntent = packageManager.getLaunchIntentForPackage(HEALTH_CONNECT_PACKAGE)
			if (launchIntent != null) {
				launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
				startActivity(launchIntent)
				result.success(true)
				return
			}

			val storeIntent = Intent(
				Intent.ACTION_VIEW,
				Uri.parse("market://details?id=$HEALTH_CONNECT_PACKAGE"),
			).apply {
				setPackage("com.android.vending")
				addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			}
			startActivity(storeIntent)
			result.success(true)
		} catch (_: Exception) {
			result.success(false)
		}
	}
}
