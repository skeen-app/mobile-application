package com.skeen.skeen

import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.view.View
import io.flutter.plugin.platform.PlatformView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * GLSurfaceView-based [PlatformView] that hosts the ARCore camera feed.
 *
 * Owns the OES texture used by ARCore as the camera image target. The
 * renderer drives [SkeenArPlugin.updateSession] each frame on the GL thread
 * — this is the *only* place where [com.google.ar.core.Session.update] is
 * invoked, so all hit-test / projection callers can read the cached frame
 * from any thread.
 */
class ArCoreView(
    context: Context,
    @Suppress("UNUSED_PARAMETER") id: Int,
    @Suppress("UNUSED_PARAMETER") creationParams: Map<String?, Any?>?,
    private val plugin: SkeenArPlugin
) : PlatformView, GLSurfaceView.Renderer {

    private val glView: GLSurfaceView = GLSurfaceView(context)
    private var textureId = -1
    private var isGlInitialized = false

    private val quadCoords = floatArrayOf(
        -1.0f, -1.0f,
        -1.0f, 1.0f,
        1.0f, -1.0f,
        1.0f, 1.0f
    )
    private val quadTexCoords = floatArrayOf(
        0.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 1.0f,
        1.0f, 0.0f
    )

    private lateinit var vertexBuffer: FloatBuffer
    private lateinit var texBuffer: FloatBuffer
    private var shaderProgram = 0
    private var posAttrib = 0
    private var texAttrib = 0

    init {
        glView.setEGLContextClientVersion(2)
        glView.preserveEGLContextOnPause = true
        glView.setRenderer(this)
        glView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

        val bb = ByteBuffer.allocateDirect(quadCoords.size * 4)
            .order(ByteOrder.nativeOrder())
        vertexBuffer = bb.asFloatBuffer().apply { put(quadCoords); position(0) }

        val tb = ByteBuffer.allocateDirect(quadTexCoords.size * 4)
            .order(ByteOrder.nativeOrder())
        texBuffer = tb.asFloatBuffer().apply { put(quadTexCoords); position(0) }
    }

    override fun getView(): View = glView

    override fun dispose() {
        // Plugin owns Session lifecycle; nothing to release here.
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)

        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        val vertexShaderSource = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = a_Position;
                v_TexCoord = a_TexCoord;
            }
        """.trimIndent()

        val fragmentShaderSource = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, v_TexCoord);
            }
        """.trimIndent()

        val vs = loadShader(GLES20.GL_VERTEX_SHADER, vertexShaderSource)
        val fs = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentShaderSource)
        shaderProgram = GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, vs)
            GLES20.glAttachShader(it, fs)
            GLES20.glLinkProgram(it)
        }
        posAttrib = GLES20.glGetAttribLocation(shaderProgram, "a_Position")
        texAttrib = GLES20.glGetAttribLocation(shaderProgram, "a_TexCoord")

        // Bind the OES texture to ARCore. resume() is called inside the
        // plugin once both texture and session are ready.
        plugin.setCameraTextureName(textureId)
        isGlInitialized = true
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        plugin.setDisplayGeometry(width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        if (!isGlInitialized) return

        val frame = plugin.updateSession() ?: return

        GLES20.glUseProgram(shaderProgram)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)

        GLES20.glEnableVertexAttribArray(posAttrib)
        GLES20.glVertexAttribPointer(posAttrib, 2, GLES20.GL_FLOAT, false, 8, vertexBuffer)

        GLES20.glEnableVertexAttribArray(texAttrib)
        val transformedTexCoords = plugin.getTransformedTexCoords(quadTexCoords)
        val transformedBuffer = ByteBuffer.allocateDirect(transformedTexCoords.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(transformedTexCoords); position(0) }
        GLES20.glVertexAttribPointer(texAttrib, 2, GLES20.GL_FLOAT, false, 8, transformedBuffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(posAttrib)
        GLES20.glDisableVertexAttribArray(texAttrib)

        // Suppress unused warning for the precomputed identity buffer; kept
        // for parity with ARCore samples that may switch to it under
        // unchanged display geometry.
        @Suppress("UnusedExpression") texBuffer
        @Suppress("UnusedExpression") frame
    }

    private fun loadShader(type: Int, code: String): Int {
        return GLES20.glCreateShader(type).also { shader ->
            GLES20.glShaderSource(shader, code)
            GLES20.glCompileShader(shader)
        }
    }
}
