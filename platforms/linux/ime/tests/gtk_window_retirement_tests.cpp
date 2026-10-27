#include "fcitx/gtk_window_retirement.hpp"
#include <cstdlib>
#include <iostream>

int main(int argc, char** argv) {
    if (!gtk_init_check(&argc, &argv)) return 1;
    auto* window = gtk_window_new(GTK_WINDOW_POPUP);
    gtk_container_add(GTK_CONTAINER(window), gtk_label_new("candidate"));
    for (int cycle = 0; cycle < 3; ++cycle) {
        gtk_widget_show_all(window);
        while (g_main_context_pending(nullptr)) g_main_context_iteration(nullptr, FALSE);
        int ticks = 0;
        const auto idle = g_idle_add(+[](gpointer value) -> gboolean {
            ++*static_cast<int*>(value);
            return G_SOURCE_CONTINUE;
        }, &ticks);
        rimes::linuxime::RetireGtkWindow(window);
        g_source_remove(idle);
        if (gtk_widget_get_visible(window) || gtk_widget_get_mapped(window) || ticks == 0 || ticks > 32) {
            std::cerr << "matrix retirement failed or unbounded GTK dispatch\n";
            return 1;
        }
    }
    gtk_widget_destroy(window);
    rimes::linuxime::RetireGtkWindow(nullptr);
    std::cout << "GTK candidate retirement OK\n";
}
