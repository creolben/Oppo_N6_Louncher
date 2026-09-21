package com.launcher.chronofold.mylauncher

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import java.util.Random
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * The ambient half of the ChronoFold hybrid theme.
 *
 * This service deliberately contains no launcher, app, or keyguard behavior.
 * It is a user-selectable Android live wallpaper that carries the launcher's
 * Luminous Horizon motion beyond HOME without asking for root or replacing
 * ColorOS system surfaces.
 */
class CosmicLiveWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = CosmicEngine()

    private inner class CosmicEngine : Engine() {
        private val frameHandler = Handler(Looper.getMainLooper())
        private val random = Random(0xC051CL)
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
        }

        private var renderHolder: SurfaceHolder? = null
        private var surfaceWidth = 0
        private var surfaceHeight = 0
        private var isVisible = false
        private var horizontalOffset = 0.5f
        private var verticalOffset = 0.5f
        private var stars: List<Star> = emptyList()

        private val drawRunnable = Runnable { drawFrame() }

        override fun onVisibilityChanged(visible: Boolean) {
            isVisible = visible
            if (visible) {
                drawFrame()
            } else {
                frameHandler.removeCallbacks(drawRunnable)
            }
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            renderHolder = holder
            drawFrame()
        }

        override fun onSurfaceChanged(
            holder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            super.onSurfaceChanged(holder, format, width, height)
            renderHolder = holder
            if (surfaceWidth != width || surfaceHeight != height) {
                surfaceWidth = width
                surfaceHeight = height
                rebuildStarfield()
            }
            drawFrame()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            frameHandler.removeCallbacks(drawRunnable)
            renderHolder = null
            super.onSurfaceDestroyed(holder)
        }

        override fun onOffsetsChanged(
            xOffset: Float,
            yOffset: Float,
            xOffsetStep: Float,
            yOffsetStep: Float,
            xPixelOffset: Int,
            yPixelOffset: Int,
        ) {
            horizontalOffset = xOffset
            verticalOffset = yOffset
            if (isVisible) drawFrame()
        }

        override fun onDestroy() {
            frameHandler.removeCallbacks(drawRunnable)
            renderHolder = null
            super.onDestroy()
        }

        private fun rebuildStarfield() {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return

            random.setSeed(
                0xC051CL xor (surfaceWidth.toLong() shl 32) xor surfaceHeight.toLong(),
            )
            val count = if (surfaceWidth.toLong() * surfaceHeight > 2_000_000L) 180 else 128
            val palette = intArrayOf(
                Color.rgb(247, 250, 255),
                Color.rgb(221, 232, 247),
                Color.rgb(112, 217, 255),
                Color.rgb(182, 161, 255),
            )

            stars = List(count) {
                Star(
                    x = random.nextFloat(),
                    y = random.nextFloat(),
                    radius = 0.55f + random.nextFloat() * 1.7f,
                    brightness = 0.26f + random.nextFloat() * 0.72f,
                    twinkleSpeed = 0.55f + random.nextFloat() * 1.45f,
                    phase = random.nextFloat() * (PI.toFloat() * 2f),
                    color = palette[random.nextInt(palette.size)],
                    hasSpikes = random.nextFloat() > 0.88f,
                )
            }
        }

        private fun drawFrame() {
            frameHandler.removeCallbacks(drawRunnable)
            val holder = renderHolder ?: return
            if (!isVisible || surfaceWidth <= 0 || surfaceHeight <= 0) return

            val canvas = try {
                holder.lockCanvas()
            } catch (_: Exception) {
                null
            }

            if (canvas != null) {
                try {
                    drawCosmos(canvas, SystemClock.elapsedRealtime() / 1000f)
                } finally {
                    try {
                        holder.unlockCanvasAndPost(canvas)
                    } catch (_: Exception) {
                        // A destroyed surface can race the final frame.
                    }
                }
            }

            if (isVisible && renderHolder != null) {
                frameHandler.postDelayed(drawRunnable, FRAME_INTERVAL_MS)
            }
        }

        private fun drawCosmos(canvas: Canvas, seconds: Float) {
            val width = canvas.width.toFloat()
            val height = canvas.height.toFloat()
            val longestSide = max(width, height)
            val parallaxX = (horizontalOffset - 0.5f) * 38f
            val parallaxY = (verticalOffset - 0.5f) * 24f

            fillPaint.style = Paint.Style.FILL
            fillPaint.shader = RadialGradient(
                width * 0.5f,
                height * 0.48f,
                longestSide * 0.9f,
                intArrayOf(
                    Color.rgb(10, 24, 48),
                    Color.rgb(5, 10, 22),
                    Color.rgb(2, 7, 17),
                ),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, width, height, fillPaint)
            fillPaint.shader = null

            drawNebula(
                canvas = canvas,
                centerX = width * 0.3f + sin(seconds * 0.12f) * 25f + parallaxX,
                centerY = height * 0.35f + cos(seconds * 0.10f) * 20f + parallaxY,
                radius = longestSide * 0.58f,
                color = Color.rgb(182, 161, 255),
                opacity = 0.15f,
            )
            drawNebula(
                canvas = canvas,
                centerX = width * 0.7f + cos(seconds * 0.09f) * 30f - parallaxX,
                centerY = height * 0.65f + sin(seconds * 0.11f) * 25f - parallaxY,
                radius = longestSide * 0.52f,
                color = Color.rgb(112, 217, 255),
                opacity = 0.12f,
            )

            // A low cobalt wash gives the ambient renderer the same seamless
            // horizon as the Flutter home without introducing another clock.
            fillPaint.shader = LinearGradient(
                0f,
                height * 0.34f,
                0f,
                height * 0.94f,
                intArrayOf(
                    Color.TRANSPARENT,
                    colorWithAlpha(Color.rgb(100, 135, 255), 0.09f),
                    colorWithAlpha(Color.rgb(112, 217, 255), 0.05f),
                    Color.TRANSPARENT,
                ),
                floatArrayOf(0f, 0.42f, 0.72f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, width, height, fillPaint)
            fillPaint.shader = null

            drawAstrogationGrid(canvas, width, height, seconds)
            drawStars(canvas, width, height, seconds)
            drawMeteors(canvas, width, height, seconds)
            drawCore(canvas, width, height, longestSide, seconds)
        }

        private fun drawNebula(
            canvas: Canvas,
            centerX: Float,
            centerY: Float,
            radius: Float,
            color: Int,
            opacity: Float,
        ) {
            fillPaint.shader = RadialGradient(
                centerX,
                centerY,
                radius,
                intArrayOf(
                    colorWithAlpha(color, opacity),
                    colorWithAlpha(color, opacity * 0.28f),
                    Color.TRANSPARENT,
                ),
                floatArrayOf(0f, 0.48f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, canvas.width.toFloat(), canvas.height.toFloat(), fillPaint)
            fillPaint.shader = null
        }

        private fun drawAstrogationGrid(
            canvas: Canvas,
            width: Float,
            height: Float,
            seconds: Float,
        ) {
            val centerX = width * 0.5f
            val centerY = height * 0.52f
            val maxRadius = max(width, height)

            linePaint.shader = null
            linePaint.color = colorWithAlpha(Color.rgb(221, 232, 247), 0.014f)
            linePaint.strokeWidth = 1f
            canvas.drawCircle(centerX, centerY, maxRadius * 0.16f, linePaint)
            canvas.drawCircle(centerX, centerY, maxRadius * 0.31f, linePaint)
            canvas.drawCircle(centerX, centerY, maxRadius * 0.46f, linePaint)

            linePaint.color = colorWithAlpha(Color.rgb(112, 217, 255), 0.016f)
            for (index in 0 until 12) {
                val angle = seconds * 0.004f + index * PI.toFloat() / 6f
                val cosAngle = cos(angle)
                val sinAngle = sin(angle)
                canvas.drawLine(
                    centerX + cosAngle * maxRadius * 0.12f,
                    centerY + sinAngle * maxRadius * 0.12f,
                    centerX + cosAngle * maxRadius * 0.48f,
                    centerY + sinAngle * maxRadius * 0.48f,
                    linePaint,
                )
            }
        }

        private fun drawStars(canvas: Canvas, width: Float, height: Float, seconds: Float) {
            for (star in stars) {
                val wave = sin(seconds * star.twinkleSpeed + star.phase)
                val alpha = star.brightness * (0.7f + wave * 0.25f) * 0.58f
                val x = star.x * width
                val y = star.y * height

                fillPaint.color = colorWithAlpha(star.color, alpha)
                fillPaint.shader = null
                canvas.drawCircle(x, y, star.radius * 0.84f, fillPaint)

                if (star.hasSpikes && alpha > 0.34f) {
                    val spikeLength = star.radius * 3.2f * (0.86f + wave * 0.22f)
                    linePaint.shader = null
                    linePaint.color = colorWithAlpha(star.color, alpha * 0.24f)
                    linePaint.strokeWidth = 0.8f
                    canvas.drawLine(x - spikeLength, y, x + spikeLength, y, linePaint)
                    canvas.drawLine(x, y - spikeLength, x, y + spikeLength, linePaint)
                }
            }
        }

        private fun drawMeteors(canvas: Canvas, width: Float, height: Float, seconds: Float) {
            for (index in 0 until 3) {
                val cycle = (seconds * (0.065f + index * 0.008f) + index * 0.33f) % 1f
                if (cycle > 0.18f) continue

                val progress = cycle / 0.18f
                val fade = sin(progress * PI.toFloat()).coerceIn(0f, 1f)
                val startX = (-0.18f + index * 0.36f) * width
                val startY = (0.14f + index * 0.19f) * height
                val endX = startX + width * 0.48f
                val endY = startY + height * 0.2f
                val headX = startX + (endX - startX) * progress
                val headY = startY + (endY - startY) * progress
                val tailX = headX - width * 0.1f
                val tailY = headY - height * 0.042f
                val color = if (index % 2 == 0) {
                    Color.rgb(112, 217, 255)
                } else {
                    Color.rgb(182, 161, 255)
                }

                linePaint.shader = LinearGradient(
                    headX,
                    headY,
                    tailX,
                    tailY,
                    intArrayOf(
                        colorWithAlpha(Color.WHITE, fade * 0.82f),
                        colorWithAlpha(color, fade * 0.45f),
                        Color.TRANSPARENT,
                    ),
                    floatArrayOf(0f, 0.35f, 1f),
                    Shader.TileMode.CLAMP,
                )
                linePaint.strokeWidth = 1.8f + index * 0.35f
                canvas.drawLine(headX, headY, tailX, tailY, linePaint)
                linePaint.shader = null

                fillPaint.color = colorWithAlpha(Color.WHITE, fade * 0.82f)
                canvas.drawCircle(headX, headY, 2.1f + index * 0.25f, fillPaint)
            }
        }

        private fun drawCore(
            canvas: Canvas,
            width: Float,
            height: Float,
            longestSide: Float,
            seconds: Float,
        ) {
            val centerX = width * 0.5f
            val centerY = height * 0.52f
            val breath = sin(seconds * 2.2f)
            val coronaRadius = longestSide * (0.07f + breath * 0.004f)

            drawNebula(
                canvas = canvas,
                centerX = centerX,
                centerY = centerY,
                radius = coronaRadius * 2.2f,
                color = Color.rgb(112, 217, 255),
                opacity = 0.10f + breath * 0.014f,
            )

            linePaint.shader = null
            linePaint.color = colorWithAlpha(Color.rgb(247, 250, 255), 0.22f)
            linePaint.strokeWidth = 1f
            canvas.drawCircle(centerX, centerY, coronaRadius * 0.78f, linePaint)

            linePaint.color = colorWithAlpha(Color.rgb(182, 161, 255), 0.18f)
            linePaint.strokeWidth = 1f
            canvas.drawCircle(centerX, centerY, coronaRadius * 1.2f, linePaint)

            canvas.save()
            canvas.rotate(seconds * 14f, centerX, centerY)
            for (index in 0 until 8) {
                val angle = index * PI.toFloat() / 4f
                val cosAngle = cos(angle)
                val sinAngle = sin(angle)
                val inner = coronaRadius * 1.1f
                val outer = coronaRadius * 1.32f
                canvas.drawLine(
                    centerX + cosAngle * inner,
                    centerY + sinAngle * inner,
                    centerX + cosAngle * outer,
                    centerY + sinAngle * outer,
                    linePaint,
                )
            }
            canvas.restore()

            fillPaint.shader = RadialGradient(
                centerX - coronaRadius * 0.18f,
                centerY - coronaRadius * 0.2f,
                coronaRadius * 0.9f,
                intArrayOf(
                    colorWithAlpha(Color.rgb(112, 217, 255), 0.82f),
                    colorWithAlpha(Color.rgb(100, 135, 255), 0.54f),
                    Color.rgb(17, 28, 49),
                ),
                floatArrayOf(0f, 0.38f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawCircle(centerX, centerY, coronaRadius * 0.52f, fillPaint)
            fillPaint.shader = null
        }

        private fun colorWithAlpha(color: Int, alpha: Float): Int = Color.argb(
            (alpha.coerceIn(0f, 1f) * 255f).toInt(),
            Color.red(color),
            Color.green(color),
            Color.blue(color),
        )
    }

    private data class Star(
        val x: Float,
        val y: Float,
        val radius: Float,
        val brightness: Float,
        val twinkleSpeed: Float,
        val phase: Float,
        val color: Int,
        val hasSpikes: Boolean,
    )

    private companion object {
        const val FRAME_INTERVAL_MS = 40L
    }
}
