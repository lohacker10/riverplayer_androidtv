package ir.r3r.river_player

import android.content.Context
import android.os.Build
import android.util.LongSparseArray
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class RiverPlayerViewFactory(
    private val players: LongSparseArray<RiverPlayer>
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *>
        val playerId = (parameters?.get("textureId") as? Number)?.toLong()
            ?: throw IllegalArgumentException("Missing player ID")
        val player = players[playerId]
            ?: throw IllegalArgumentException("Unknown player ID $playerId")
        require(player.usesSurfaceView) { "Player $playerId was created without SurfaceView" }
        return RiverPlayerView(context, player)
    }
}

internal class RiverPlayerView(
    context: Context, private val player: RiverPlayer
) : SurfaceView(context), PlatformView, SurfaceHolder.Callback {
    private var viewDisposed = false

    init {
        isFocusable = false
        isFocusableInTouchMode = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        holder.addCallback(this)
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.N_MR1) {
            setZOrderMediaOverlay(true)
        }
    }

    override fun getView(): View = this

    override fun surfaceCreated(holder: SurfaceHolder) {
        if (!viewDisposed) player.attachSurface(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        player.detachSurface(holder.surface)
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        if (!viewDisposed && visibility == View.VISIBLE && isShown) {
            player.attachSurface(holder.surface)
        }
    }

    override fun dispose() {
        viewDisposed = true
        holder.removeCallback(this)
        player.detachSurface(holder.surface)
    }
}
