package com.localreader.ebooktts

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

class MainActivity : AudioServiceActivity() {
    private val textDecoderChannel = "local_reader/text_decoder"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, textDecoderChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "decodeBytes") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val base64 = call.argument<String>("base64")
                val charsets = call.argument<List<String>>("charsets") ?: listOf("GB18030", "GBK", "GB2312")
                if (base64.isNullOrBlank()) {
                    result.error("invalid_args", "Missing byte payload.", null)
                    return@setMethodCallHandler
                }

                try {
                    val bytes = Base64.decode(base64, Base64.NO_WRAP)
                    result.success(decodeWithCharsets(bytes, charsets))
                } catch (error: Exception) {
                    result.error("decode_failed", error.message, null)
                }
            }
    }

    private fun decodeWithCharsets(bytes: ByteArray, charsets: List<String>): String {
        for (charsetName in charsets) {
            try {
                val decoder = Charset.forName(charsetName)
                    .newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                return decoder.decode(ByteBuffer.wrap(bytes)).toString()
            } catch (_: CharacterCodingException) {
                continue
            } catch (_: IllegalArgumentException) {
                continue
            }
        }

        return Charset.forName("GB18030").decode(ByteBuffer.wrap(bytes)).toString()
    }
}
