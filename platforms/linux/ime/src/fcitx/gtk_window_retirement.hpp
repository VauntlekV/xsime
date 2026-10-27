#pragma once
#include <gtk/gtk.h>

namespace rimes::linuxime {
// The Fcitx host stops pumping GTK when no matrix is visible. Drain the
// pending unmap/frame work before that last pump is retired (Wayland #280).
// Hold GTK objects independently: dispatch may destroy the owning renderer.
inline void RetireGtkWindow(GtkWidget* window) {
    if (!window) return;
    g_object_ref(window);
    auto* display = gtk_widget_get_display(window);
    g_object_ref(display);
    gtk_widget_hide(window);
    for (int i = 0; i < 32 && g_main_context_pending(nullptr); ++i)
        g_main_context_iteration(nullptr, FALSE);
    gdk_display_flush(display);
    g_object_unref(display);
    g_object_unref(window);
}
}
