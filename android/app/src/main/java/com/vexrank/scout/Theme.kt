package com.vexrank.scout

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/// The same four palettes the iOS app offers, and the same accents - each
/// checked to clear AA on its own surface.
enum class VexTheme(val label: String, val page: Color, val surface: Color,
                    val surfaceRaised: Color, val accent: Color, val band: Color) {
    MIDNIGHT("Midnight", Color(0xFF0B0D10), Color(0xFF141821), Color(0xFF1C222E),
        Color(0xFF4FC3F7), Color(0xFF16202B)),
    EMBER("Ember", Color(0xFF100B0B), Color(0xFF1D1414), Color(0xFF281B1B),
        Color(0xFFFF5A5F), Color(0xFF2A1A1A)),
    ABYSS("Abyss", Color(0xFF07090F), Color(0xFF111726), Color(0xFF182035),
        Color(0xFF7C9CFF), Color(0xFF141C30)),
    MOSS("Moss", Color(0xFF080D0A), Color(0xFF121A16), Color(0xFF19241E),
        Color(0xFF4ADE80), Color(0xFF16231C));

    companion object {
        fun named(id: String?) = entries.firstOrNull { it.name == id } ?: MIDNIGHT
    }
}

@Composable
fun MakapakaTheme(theme: VexTheme, content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = theme.accent,
            background = theme.page,
            surface = theme.surface,
            surfaceVariant = theme.surfaceRaised,
            onPrimary = Color.White,
            onBackground = Color(0xFFF2F4F8),
            onSurface = Color(0xFFF2F4F8),
        ),
        content = content,
    )
}
