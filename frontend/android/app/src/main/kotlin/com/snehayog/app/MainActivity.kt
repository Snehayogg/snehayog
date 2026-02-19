package com.snehayog.app

import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Enable edge-to-edge display (modern approach, avoids deprecated APIs)
        // Enable edge-to-edge display manually as enableEdgeToEdge is not supported on FlutterActivity
        // enableEdgeToEdge()
        window.statusBarColor = 0 // Color.TRANSPARENT
        window.navigationBarColor = 0 // Color.TRANSPARENT
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView)?.let { controller ->
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }
}
