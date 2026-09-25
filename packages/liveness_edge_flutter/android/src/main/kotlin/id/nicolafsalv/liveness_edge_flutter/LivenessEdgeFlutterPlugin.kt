package id.nicolafsalv.liveness_edge_flutter

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin
import kotlin.math.sqrt

class LivenessEdgeFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val executor = Executors.newSingleThreadExecutor()
    private var landmarker: FaceLandmarker? = null
    private var environment: OrtEnvironment? = null
    private var antiSpoof: OrtSession? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "liveness_edge_flutter")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) = when (call.method) {
        "initialize" -> executor.execute { runCatching { initialize() }.fold(
            { post { result.success(null) } }, { post { result.error("initialize_failed", it.message, null) } }) }
        "analyze" -> {
            val bytes = call.arguments as? ByteArray
            if (bytes == null) result.error("invalid_frame", "The frame must be a byte array", null)
            else executor.execute { runCatching { analyze(bytes) }.fold(
                { value -> post { result.success(value) } },
                { error -> post { result.error("analysis_failed", error.message, null) } }) }
        }
        "close" -> executor.execute { closeModels(); post { result.success(null) } }
        else -> result.notImplemented()
    }

    private fun post(block: () -> Unit) = android.os.Handler(context.mainLooper).post(block)

    private fun initialize() {
        if (landmarker != null) return
        landmarker = FaceLandmarker.createFromOptions(context, FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("face_landmarker.task").build())
            .setRunningMode(RunningMode.IMAGE).setNumFaces(2).setOutputFaceBlendshapes(true).build())
        environment = OrtEnvironment.getEnvironment()
        antiSpoof = environment!!.createSession(context.assets.open("minifasnet_v2.onnx").use { it.readBytes() }, OrtSession.SessionOptions())
    }

    private fun analyze(data: ByteArray): Map<String, Any?> {
        initialize()
        require(data.size >= 8 && String(data, 0, 4) == "LVC1") { "Invalid frame format" }
        val width = ((data[4].toInt() and 255) shl 8) or (data[5].toInt() and 255)
        val height = ((data[6].toInt() and 255) shl 8) or (data[7].toInt() and 255)
        require(data.size == 8 + width * height * 3) { "Invalid frame dimensions" }
        val pixels = IntArray(width * height); var p = 8
        for (i in pixels.indices) { val b=data[p++].toInt()and 255; val g=data[p++].toInt()and 255; val r=data[p++].toInt()and 255; pixels[i]=-0x1000000 or(r shl 16)or(g shl 8)or b }
        val bitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        val detected = landmarker!!.detect(BitmapImageBuilder(bitmap).build())
        if (detected.faceLandmarks().size != 1) return mapOf("faceCount" to detected.faceLandmarks().size)
        val points=detected.faceLandmarks()[0]; val minX=points.minOf{it.x()}; val maxX=points.maxOf{it.x()}; val minY=points.minOf{it.y()}; val maxY=points.maxOf{it.y()}
        val blend=detected.faceBlendshapes().orElse(emptyList()).getOrNull(0).orEmpty().associate{it.categoryName() to it.score()}
        val eyesDetected=blend.containsKey("eyeBlinkLeft")&&blend.containsKey("eyeBlinkRight")
        val eyesOpen=maxOf(blend["eyeBlinkLeft"]?:1f,blend["eyeBlinkRight"]?:1f)<.55f
        val left=points[33]; val right=points[263]; val nose=points[1]; val dx=right.x()-left.x(); val dy=right.y()-left.y()
        val offset=((nose.x()-(left.x()+right.x())/2)*dx+(nose.y()-(left.y()+right.y())/2)*dy)/(dx*dx+dy*dy)
        return mapOf("faceCount" to 1,"eyesDetected" to eyesDetected,"eyesOpen" to eyesOpen,"faceCenterX" to ((minX+maxX)/2).toDouble(),"faceCenterY" to ((minY+maxY)/2).toDouble(),
            "faceWidth" to (maxX-minX).toDouble(),"faceHeight" to (maxY-minY).toDouble(),"lighting" to lighting(bitmap,minX,minY,maxX,maxY),
            "yaw" to Math.toDegrees(atan2((2*offset).toDouble(),1.0)),"liveScore" to passive(bitmap,minX,minY,maxX,maxY),
            "faceIdentity" to faceIdentity(points))
    }

    private fun faceIdentity(points: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>): List<Double> {
        val left=points[33];val right=points[263];val dx=right.x()-left.x();val dy=right.y()-left.y()
        val scale=sqrt(dx*dx+dy*dy).coerceAtLeast(.0001f);val angle=atan2(dy,dx);val c=cos(angle);val s=sin(angle)
        val cx=(left.x()+right.x())/2;val cy=(left.y()+right.y())/2
        // Use rigid face regions across the contour, eyes, brows, and nose.
        // Mouth landmarks are intentionally excluded because a blink challenge
        // should not fail merely because the user changes expression.
        val indices=intArrayOf(
            10, 152, 127, 356, 234, 454, 93, 323, 132, 361,
            33, 133, 159, 145, 263, 362, 386, 374,
            70, 105, 107, 336, 334, 300,
            1, 2, 4, 5, 168, 197, 195, 6
        )
        return indices.flatMap { index -> val point=points[index];val x=point.x()-cx;val y=point.y()-cy
            listOf(((x*c+y*s)/scale).toDouble(),((-x*s+y*c)/scale).toDouble()) }
    }

    private fun lighting(bitmap:Bitmap,x0:Float,y0:Float,x1:Float,y1:Float):String? {
        var sum=0.0; var count=0; val l=(x0*bitmap.width).toInt().coerceIn(0,bitmap.width-1); val r=(x1*bitmap.width).toInt().coerceIn(l+1,bitmap.width)
        val t=(y0*bitmap.height).toInt().coerceIn(0,bitmap.height-1); val b=(y1*bitmap.height).toInt().coerceIn(t+1,bitmap.height)
        for(y in t until b step 4)for(x in l until r step 4){val c=bitmap.getPixel(x,y);sum+=.299*(c shr 16 and 255)+.587*(c shr 8 and 255)+.114*(c and 255);count++}
        val mean=sum/count.coerceAtLeast(1);return if(mean<55)"dark" else if(mean>205)"bright" else null
    }

    private fun passive(bitmap:Bitmap,x0:Float,y0:Float,x1:Float,y1:Float):Double {
        val faceW=(x1-x0)*bitmap.width;val faceH=(y1-y0)*bitmap.height;val scale=minOf((bitmap.width-1)/faceW,(bitmap.height-1)/faceH,2.7f)
        val cropW=(faceW*scale).toInt();val cropH=(faceH*scale).toInt();val cx=(x0+x1)*bitmap.width/2;val cy=(y0+y1)*bitmap.height/2
        val l=(cx-cropW/2).toInt().coerceIn(0,bitmap.width-1-cropW);val t=(cy-cropH/2).toInt().coerceIn(0,bitmap.height-1-cropH)
        val crop=Bitmap.createBitmap(bitmap,l,t,cropW+1,cropH+1);val scaled=Bitmap.createScaledBitmap(crop,80,80,true);val input=FloatArray(19200)
        for(y in 0 until 80)for(x in 0 until 80){val c=scaled.getPixel(x,y);val i=y*80+x;input[i]=(c and 255).toFloat();input[6400+i]=(c shr 8 and 255).toFloat();input[12800+i]=(c shr 16 and 255).toFloat()}
        val session=antiSpoof!!;OnnxTensor.createTensor(environment!!,FloatBuffer.wrap(input),longArrayOf(1,3,80,80)).use{tensor->session.run(mapOf(session.inputNames.first() to tensor)).use{out->
            val logits=(out[0].value as Array<*>)[0] as FloatArray;val maximum=logits.max();val values=logits.map{exp((it-maximum).toDouble())};return values[1]/values.sum()}}
    }

    private fun closeModels(){landmarker?.close();landmarker=null;antiSpoof?.close();antiSpoof=null;environment?.close();environment=null}
    override fun onDetachedFromEngine(binding:FlutterPlugin.FlutterPluginBinding){channel.setMethodCallHandler(null);closeModels();executor.shutdown()}
}
