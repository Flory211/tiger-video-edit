package com.leos.leos_fast_video_edit

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

@UnstableApi
class MainActivity: FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var done = false
    private var failure: String? = null
    private var output: String? = null
    private var expectedDurationUs = 0L
    private var saveResult: MethodChannel.Result? = null
    private var savePath: String? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "tiger/media").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "waveform" -> {
                        val path = call.argument<String>("path")!!
                        val duration = call.argument<Number>("durationUs")!!.toLong()
                        val count = (call.argument<Number>("bins")?.toInt() ?: 2000).coerceIn(1, 1000000)
                        worker.execute {
                            try { val bins = decodeWave(path, duration, count); main.post { result.success(bins.toList()) } }
                            catch (e: Exception) { main.post { result.error("decode", e.message, null) } }
                        }
                    }
                    "inspectVideo", "videoFrame" -> {
                        val path = call.argument<String>("path")!!
                        val timeUs = call.argument<Number>("timeUs")?.toLong() ?: 0L
                        val limit = (call.argument<Number>("maxDimension")?.toInt() ?: 1920).coerceIn(1, 8192)
                        worker.execute {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(path)
                                val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt()
                                val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt()
                                val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
                                if (call.method == "inspectVideo") {
                                    val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong() * 1000L
                                    val swap = rotation == 90 || rotation == 270
                                    val metadata = mapOf("durationUs" to duration, "width" to if(swap) height else width, "height" to if(swap) width else height)
                                    main.post { result.success(metadata) }
                                } else {
                                    val scale = min(1.0, limit.toDouble() / max(width, height))
                                    val frame = if (android.os.Build.VERSION.SDK_INT >= 27) {
                                        retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST, max(1, (width * scale).toInt()), max(1, (height * scale).toInt()))
                                    } else retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                                    check(frame != null) { "Не удалось декодировать кадр" }
                                    try {
                                        val frameScale = min(1.0, limit.toDouble() / max(frame.width, frame.height))
                                        val scaled = if (frameScale < 1) Bitmap.createScaledBitmap(frame, max(1, (frame.width * frameScale).toInt()), max(1, (frame.height * frameScale).toInt()), true) else frame
                                        try {
                                            val bytes = ByteArrayOutputStream().use { stream ->
                                                check(scaled.compress(Bitmap.CompressFormat.PNG, 100, stream))
                                                stream.toByteArray()
                                            }
                                            main.post { result.success(bytes) }
                                        } finally { if (scaled !== frame) scaled.recycle() }
                                    } finally { frame.recycle() }
                                }
                            } catch (e: Exception) { main.post { result.error("decode", e.message, null) } }
                            finally { retriever.release() }
                        }
                    }
                    "startExport" -> {
                        check(transformer == null) { "Экспорт уже выполняется" }
                        ensureEncoder("video/avc"); ensureEncoder("audio/mp4a-latm")
                        done = false; failure = null
                        val audio = call.argument<String>("audio")!!
                        val start = call.argument<Number>("startUs")!!.toLong()
                        val duration = call.argument<Number>("durationUs")!!.toLong()
                        val path = call.argument<String>("output")!!
                        output = path; expectedDurationUs = duration
                        val items = call.argument<List<Map<String, Any>>>("segments")!!.map { s ->
                            val frames = (s["frames"] as Number).toLong()
                            val itemDuration = frames * 1000000L / 30L
                            val media = MediaItem.Builder().setUri(Uri.fromFile(File(s["path"] as String)))
                                .setImageDurationMs((itemDuration + 999L) / 1000L).build()
                            EditedMediaItem.Builder(media).setDurationUs(itemDuration).setFrameRate(30).setRemoveAudio(true).build()
                        }
                        val audioMedia = MediaItem.Builder().setUri(Uri.fromFile(File(audio)))
                            .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionUs(start).setEndPositionUs(start + duration).build()).build()
                        val sound = EditedMediaItem.Builder(audioMedia).setRemoveVideo(true).build()
                        val composition = Composition.Builder(
                            EditedMediaItemSequence.withVideoFrom(items),
                            EditedMediaItemSequence.withAudioFrom(listOf(sound))).build()
                        val job = Transformer.Builder(this)
                            .setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                            .addListener(object: Transformer.Listener {
                                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                                    worker.execute {
                                        try { validateOutput(path, expectedDurationUs); main.post { done = true; transformer = null } }
                                        catch (e: Exception) { main.post { failure = e.message ?: "Проверка MP4 не удалась"; transformer = null } }
                                    }
                                }
                                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                                    failure = exportException.message ?: "Ошибка кодировщика"; transformer = null
                                }
                            }).build()
                        transformer = job
                        job.start(composition, path)
                        result.success(null)
                    }
                    "exportStatus" -> {
                        val progress = ProgressHolder()
                        transformer?.getProgress(progress)
                        result.success(mapOf("done" to done, "error" to failure, "progress" to if(done) 1.0 else progress.progress / 100.0))
                    }
                    "cancel" -> {
                        transformer?.cancel(); transformer = null; done = false; failure = "Экспорт отменён"
                        output?.let { File(it).delete() }; result.success(null)
                    }
                    "saveVideo" -> {
                        check(saveResult == null) { "Диалог сохранения уже открыт" }
                        savePath = call.argument<String>("path")!!
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE); type = "video/mp4"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "Tiger.mp4")
                        }
                        saveResult = result
                        startActivityForResult(intent, 741)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("media", e.message, null) }
        }
    }

    private fun ensureEncoder(mime: String) {
        val found = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any {
            it.isEncoder && it.supportedTypes.any { type -> type.equals(mime, ignoreCase = true) }
        }
        check(found) { "На устройстве недоступен кодировщик $mime" }
    }

    private fun validateOutput(path: String, durationUs: Long) {
        check(File(path).length() > 100L) { "Видео не создано" }
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var video = false; var audio = false
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                when (format.getString(MediaFormat.KEY_MIME)) {
                    "video/avc" -> {
                        video = true
                        if(format.containsKey(MediaFormat.KEY_DURATION)) {
                            check(abs(format.getLong(MediaFormat.KEY_DURATION) - durationUs) < 160000L) { "Некорректная длительность видео" }
                        }
                    }
                    "audio/mp4a-latm" -> audio = true
                }
            }
            check(video && audio) { "Не найдены дорожки H.264 и AAC" }
        } finally { extractor.release() }
    }

    @Deprecated("Legacy activity result bridge used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 741) return
        val pending = saveResult ?: return
        saveResult = null
        val source = savePath; savePath = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || source == null) { pending.success(null); return }
        worker.execute {
            try {
                val expected = File(source).length()
                val copied = contentResolver.openOutputStream(uri, "w")!!.use { out -> File(source).inputStream().use { it.copyTo(out) } }
                check(copied == expected) { "Файл скопирован не полностью" }
                main.post { pending.success(uri.toString()) }
            } catch (e: Exception) {
                try { contentResolver.delete(uri, null, null) } catch (_: Exception) { }
                main.post { pending.error("save", e.message, null) }
            }
        }
    }

    private fun decodeWave(path: String, durationUs: Long, binCount: Int): DoubleArray {
        val bins = DoubleArray(binCount)
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
                ?: error("Нет звуковой дорожки")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder; decoder.configure(format, null, null, 0); decoder.start()
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floatPcm = false
            var inputDone = false; var finished = false
            val info = MediaCodec.BufferInfo()
            var lastProgress = System.nanoTime()
            while (!finished) {
                check(System.nanoTime() - lastProgress < 30000000000L) { "Декодер не отвечает" }
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val buffer = decoder.getInputBuffer(index)!!
                        val count = extractor.readSampleData(buffer, 0)
                        if (count < 0) { decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true }
                        else { decoder.queueInputBuffer(index, 0, count, extractor.sampleTime, 0); extractor.advance() }
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, 10000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val out = decoder.outputFormat
                    rate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE); channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    floatPcm = out.containsKey(MediaFormat.KEY_PCM_ENCODING) && out.getInteger(MediaFormat.KEY_PCM_ENCODING) == 4
                }
                if (index >= 0) {
                    lastProgress = System.nanoTime()
                    val buffer = decoder.getOutputBuffer(index)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buffer.position(info.offset); buffer.limit(info.offset + info.size)
                    var sample = 0
                    while (buffer.remaining() >= if(floatPcm) 4 else 2) {
                        val amplitude = if(floatPcm) abs(buffer.float.toDouble()) else abs(buffer.short.toDouble() / 32768.0)
                        val us = info.presentationTimeUs + sample.toLong() * 1000000L / max(1, rate * channels)
                        val bin = min(binCount - 1, max(0, (us * binCount.toLong() / max(1L, durationUs)).toInt()))
                        bins[bin] = max(bins[bin], min(1.0, amplitude)); sample++
                    }
                    finished = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    decoder.releaseOutputBuffer(index, false)
                }
            }
            return bins
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            codec?.release(); extractor.release()
        }
    }
    override fun onDestroy() { transformer?.cancel(); worker.shutdown(); super.onDestroy() }
}

