package dev.androfest.android.features.dashboard

import android.animation.ValueAnimator
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

private val Night =
    darkColorScheme(
        primary = Color(0xFFBEADFF),
        onPrimary = Color(0xFF241542),
        primaryContainer = Color(0xFF382957),
        onPrimaryContainer = Color(0xFFEADDFF),
        secondary = Color(0xFFCAF59A),
        onSecondary = Color(0xFF19320A),
        secondaryContainer = Color(0xFF293F1C),
        onSecondaryContainer = Color(0xFFCAF59A),
        background = Color(0xFF101222),
        onBackground = Color(0xFFF5F3FF),
        surface = Color(0xFF1C2036),
        onSurface = Color(0xFFF5F3FF),
        surfaceVariant = Color(0xFF292D45),
        onSurfaceVariant = Color(0xFFB8BCD3),
        outline = Color(0xFF8589A1),
        outlineVariant = Color(0xFF40445B),
    )
private val Day =
    lightColorScheme(
        primary = Color(0xFF6543B5),
        onPrimary = Color.White,
        primaryContainer = Color(0xFFEADDFF),
        onPrimaryContainer = Color(0xFF281346),
        secondary = Color(0xFF376514),
        onSecondary = Color.White,
        secondaryContainer = Color(0xFFD5F6B6),
        onSecondaryContainer = Color(0xFF19320A),
        background = Color(0xFFF5F3FC),
        onBackground = Color(0xFF202036),
        surface = Color.White,
        onSurface = Color(0xFF202036),
        surfaceVariant = Color(0xFFECE8F5),
        onSurfaceVariant = Color(0xFF5F6178),
        outline = Color(0xFF75758B),
        outlineVariant = Color(0xFFD6D2E4),
    )

@Composable
fun AndrofestTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) Night else Day, content = content)
}

/** Motion exists only while the activity is resumed; system-disabled animations stay static. */
@Composable
private fun orbitAngle(): Float {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var active by remember {
        mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
    }
    var motion by remember { mutableStateOf(ValueAnimator.areAnimatorsEnabled()) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, _ ->
            active = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            motion = ValueAnimator.areAnimatorsEnabled()
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    if (!active || !motion) return 35f
    val transition = rememberInfiniteTransition(label = "connection orbit")
    val angle by
        transition.animateFloat(
            0f,
            360f,
            infiniteRepeatable(tween(12000, easing = LinearEasing)),
            label = "orbit rotation",
        )
    return angle
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ConnectionHero(name: String, connected: Boolean, status: String) {
    val colors = MaterialTheme.colorScheme
    val angle = orbitAngle()
    Card(
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
    ) {
        Column(
            Modifier.fillMaxWidth()
                .background(
                    Brush.linearGradient(
                        listOf(
                            colors.primary.copy(alpha = 0.14f),
                            colors.surface,
                            colors.secondary.copy(alpha = 0.06f),
                        )
                    )
                )
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Canvas(Modifier.size(80.dp)) {
                    drawCircle(colors.primary.copy(alpha = 0.09f))
                    drawCircle(
                        colors.primary.copy(alpha = 0.18f),
                        radius = size.minDimension * 0.43f,
                        style = Stroke(1.dp.toPx()),
                    )
                    rotate(angle) {
                        drawArc(
                            Brush.sweepGradient(
                                listOf(
                                    colors.primary.copy(alpha = 0.1f),
                                    colors.primary,
                                    colors.secondary,
                                )
                            ),
                            0f,
                            if (connected) 260f else 100f,
                            false,
                            topLeft = Offset(6.dp.toPx(), 6.dp.toPx()),
                            size = Size(size.width - 12.dp.toPx(), size.height - 12.dp.toPx()),
                            style = Stroke(3.dp.toPx(), cap = StrokeCap.Round),
                        )
                    }
                    drawRoundRect(
                        colors.onSurface,
                        Offset(size.width * .35f, size.height * .27f),
                        Size(size.width * .30f, size.height * .46f),
                        CornerRadius(5.dp.toPx()),
                        style = Stroke(2.dp.toPx()),
                    )
                    drawLine(
                        colors.onSurface,
                        Offset(size.width * .46f, size.height * .66f),
                        Offset(size.width * .54f, size.height * .66f),
                        2.dp.toPx(),
                        cap = StrokeCap.Round,
                    )
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        if (connected) "CONNECTED" else "WAITING FOR CONNECTION",
                        color = if (connected) colors.secondary else colors.primary,
                        style = MaterialTheme.typography.labelSmall,
                        fontFamily = FontFamily.Monospace,
                    )
                    Text(
                        name,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics { heading() },
                    )
                }
            }
            Text(
                if (connected) "One flow.\nBoth devices." else "Meet your\nMac.",
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold,
            )
            Text(
                status,
                style = MaterialTheme.typography.bodyMedium,
                color = colors.onSurfaceVariant,
            )
            if (connected)
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    StatusPill("Bluetooth LE")
                    StatusPill("Encrypted")
                }
        }
    }
}

@Composable
fun StatusPill(text: String) {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(50)) {
        Text(
            text,
            Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.onSecondaryContainer,
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
fun SectionHeading(title: String, subtitle: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.padding(vertical = 8.dp),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            subtitle,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
fun NavGlyph(index: Int) {
    val color = LocalContentColor.current
    Canvas(Modifier.size(24.dp)) {
        val stroke = Stroke(2.dp.toPx(), cap = StrokeCap.Round)
        when (index) {
            0 -> {
                drawRoundRect(
                    color,
                    Offset(size.width * .25f, size.height * .08f),
                    Size(size.width * .5f, size.height * .84f),
                    CornerRadius(4.dp.toPx()),
                    style = stroke,
                )
                drawLine(
                    color,
                    Offset(size.width * .43f, size.height * .76f),
                    Offset(size.width * .57f, size.height * .76f),
                    stroke.width,
                )
            }
            1 -> {
                drawLine(
                    color,
                    Offset(size.width * .25f, size.height * .28f),
                    Offset(size.width * .75f, size.height * .28f),
                    stroke.width,
                    StrokeCap.Round,
                )
                drawLine(
                    color,
                    Offset(size.width * .75f, size.height * .72f),
                    Offset(size.width * .25f, size.height * .72f),
                    stroke.width,
                    StrokeCap.Round,
                )
                drawLine(
                    color,
                    Offset(size.width * .6f, size.height * .12f),
                    Offset(size.width * .76f, size.height * .28f),
                    stroke.width,
                    StrokeCap.Round,
                )
                drawLine(
                    color,
                    Offset(size.width * .4f, size.height * .88f),
                    Offset(size.width * .24f, size.height * .72f),
                    stroke.width,
                    StrokeCap.Round,
                )
            }
            else -> {
                for (row in 0..2) {
                    val y = size.height * (.22f + row * .28f)
                    drawLine(
                        color,
                        Offset(size.width * .12f, y),
                        Offset(size.width * .88f, y),
                        stroke.width,
                        StrokeCap.Round,
                    )
                    drawCircle(
                        color,
                        3.dp.toPx(),
                        Offset(size.width * (if (row == 1) .66f else .34f), y),
                    )
                }
            }
        }
    }
}
