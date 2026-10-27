#include "practice_editor.hpp"
#include "typing_practice_core.hpp"
#include <cstring>
#include <algorithm>

namespace rimes::desktop {
void ConfigurePracticeInput() {
    // Fcitx's optional GTK snooper consumes preedit keys before widget handlers.
    // Use GTK's regular widget/IM-context path in this process only.
    // https://github.com/fcitx/fcitx5-gtk/blob/5.1.1/gtk3/fcitximcontext.cpp
    g_setenv("FCITX_DISABLE_SNOOPER", "1", TRUE);
}
PracticeEditor::PracticeEditor()
    : view_(Class(gtk_text_view_new(), "practice-editor")),
      buffer_(gtk_text_view_get_buffer(GTK_TEXT_VIEW(view_))) {
    g_object_ref_sink(view_);
    g_object_ref(buffer_);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view_), GTK_WRAP_WORD_CHAR);
    gtk_text_view_set_left_margin(GTK_TEXT_VIEW(view_), 19);
    gtk_text_view_set_right_margin(GTK_TEXT_VIEW(view_), 19);
    gtk_text_view_set_top_margin(GTK_TEXT_VIEW(view_), 12);
    gtk_text_view_set_bottom_margin(GTK_TEXT_VIEW(view_), 12);
    gtk_text_view_set_input_purpose(GTK_TEXT_VIEW(view_), GTK_INPUT_PURPOSE_FREE_FORM);
    gtk_text_view_set_input_hints(
        GTK_TEXT_VIEW(view_),
        static_cast<GtkInputHints>(GTK_INPUT_HINT_NO_SPELLCHECK | GTK_INPUT_HINT_NO_EMOJI));
    atk_object_set_name(gtk_widget_get_accessible(view_), "跟打输入，首键计时，组字不判错");
    Enable(false);
    auto* font_style = gtk_css_provider_new();
    gtk_css_provider_load_from_data(font_style, "textview.practice-editor { font-family: 'Noto Sans CJK SC'; font-size: 22px; }", -1, nullptr);
    gtk_style_context_add_provider(gtk_widget_get_style_context(view_), GTK_STYLE_PROVIDER(font_style), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
    g_object_unref(font_style);
    g_signal_connect(view_, "size-allocate", G_CALLBACK(+[](GtkWidget* widget, GtkAllocation* allocation, gpointer data) {
        auto* self = static_cast<PracticeEditor*>(data);
        const auto columns = std::max(4, (allocation->width - 38) / 28);
        if (self->track_ && columns != self->columns_) { self->columns_ = columns; self->LayoutTrack(); }
        (void)widget;
    }), this);
    g_signal_connect_after(view_, "draw", G_CALLBACK(+[](GtkWidget*, cairo_t* cr, gpointer data) -> gboolean {
        static_cast<PracticeEditor*>(data)->DrawTrack(cr); return FALSE;
    }), this);
    g_signal_connect(view_, "drag-motion",
                     G_CALLBACK(+[](GtkWidget *, GdkDragContext *drag, gint, gint, guint time,
                                    gpointer) -> gboolean {
                         gdk_drag_status(drag, static_cast<GdkDragAction>(0), time);
                         return TRUE;
                     }),
                     this);
    g_signal_connect(view_, "drag-drop",
                     G_CALLBACK(+[](GtkWidget *, GdkDragContext *, gint, gint, guint,
                                    gpointer data) -> gboolean {
                         static_cast<PracticeEditor *>(data)->Reject();
                         return TRUE;
                     }),
                     this);
    g_signal_connect(view_, "drag-data-received",
                     G_CALLBACK(+[](GtkWidget *widget, GdkDragContext *, gint, gint,
                                    GtkSelectionData *, guint, guint, gpointer data) {
                         g_signal_stop_emission_by_name(widget, "drag-data-received");
                         static_cast<PracticeEditor *>(data)->Reject();
                     }),
                     this);
    g_signal_connect(view_, "key-press-event",
                     G_CALLBACK(+[](GtkWidget *, GdkEventKey *e, gpointer data) -> gboolean {
                         auto *s = static_cast<PracticeEditor *>(data);
                         if (!s->enabled_)
                             return TRUE;
                         const auto modifiers = GDK_CONTROL_MASK | GDK_MOD1_MASK | GDK_SUPER_MASK |
                                                GDK_META_MASK | GDK_HYPER_MASK;
                         const bool shortcut = (e->state & modifiers) != 0;
                         if ((shortcut && (e->keyval == GDK_KEY_v || e->keyval == GDK_KEY_V)) ||
                             ((e->state & GDK_SHIFT_MASK) && e->keyval == GDK_KEY_Insert)) {
                             s->Reject();
                             return TRUE;
                         }
                         if (shortcut || e->is_modifier)
                             return FALSE;
                         const auto unicode = gdk_keyval_to_unicode(e->keyval);
                         const bool printable =
                             (unicode >= 32 && !g_unichar_iscntrl(unicode) &&
                              !(unicode >= 0xf700 && unicode <= 0xf8ff)) ||
                             (e->keyval >= GDK_KEY_dead_grave && e->keyval <= GDK_KEY_dead_greek);
                         const bool backspace = e->keyval == GDK_KEY_BackSpace;
                         if (!printable && !backspace && e->keyval != GDK_KEY_Return &&
                             e->keyval != GDK_KEY_KP_Enter && e->keyval != GDK_KEY_Tab &&
                             e->keyval != GDK_KEY_ISO_Left_Tab && e->keyval != GDK_KEY_Delete)
                             return FALSE;
                         const auto stamp = std::make_pair(e->time, e->hardware_keycode);
                         // Fcitx can forward an unhandled event. That is the original physical
                         // press, not a second key. Genuine auto-repeat has a new timestamp.
                         if (s->seen_.insert(stamp).second) {
                             if (s->seen_.size() > 256)
                                 s->seen_.erase(s->seen_.begin());
                             const bool repeat = !s->down_.insert(e->hardware_keycode).second;
                             if (s->key)
                                 s->key(e->time, e->hardware_keycode, repeat, backspace,
                                        s->composing_);
                         }
                         return FALSE;
                     }),
                     this);
    g_signal_connect(view_, "key-release-event",
                     G_CALLBACK(+[](GtkWidget *, GdkEventKey *e, gpointer data) -> gboolean {
                         static_cast<PracticeEditor *>(data)->down_.erase(e->hardware_keycode);
                         return FALSE;
                     }),
                     this);
    g_signal_connect(view_, "preedit-changed",
                     G_CALLBACK(+[](GtkTextView *, const gchar *text, gpointer data) {
                         auto *s = static_cast<PracticeEditor *>(data);
                         s->composing_ = text && *text;
                         if (s->enabled_ && s->composing_ && s->composition)
                             s->composition();
                         if (!s->composing_)
                             s->Publish();
                     }),
                     this);
    g_signal_connect(buffer_, "begin-user-action", G_CALLBACK(+[](GtkTextBuffer *, gpointer data) {
                         auto *s = static_cast<PracticeEditor *>(data);
                         if (!s->depth_) {
                             s->before_action_ = s->Text();
                             s->rejected_action_ = false;
                         }
                         ++s->depth_;
                     }),
                     this);
    g_signal_connect(buffer_, "end-user-action", G_CALLBACK(+[](GtkTextBuffer *, gpointer data) {
                         auto *s = static_cast<PracticeEditor *>(data);
                         if (s->depth_)
                             --s->depth_;
                         if (!s->depth_ && s->rejected_action_) {
                             s->suppressed_ = true;
                             gtk_text_buffer_set_text(s->buffer_, s->before_action_.c_str(),
                                                      s->before_action_.size());
                             s->suppressed_ = false;
                             s->dirty_ = false;
                             s->insertion_.reset();
                             s->rejected_action_ = false;
                         }
                         s->Publish();
                     }),
                     this);
    g_signal_connect(
        buffer_, "insert-text",
        G_CALLBACK(+[](GtkTextBuffer *b, GtkTextIter *at, gchar *text, gint size, gpointer data) {
            auto *s = static_cast<PracticeEditor *>(data);
            if (s->suppressed_)
                return;
            try {
                if (!s->enabled_ || size < 0 || size > rimes::practice::kMaximumTextBytes ||
                    !g_utf8_validate(text, size, nullptr))
                    throw std::runtime_error("invalid insert");
                auto candidate = s->Text();
                const int scalar = gtk_text_iter_get_offset(at);
                const auto offset =
                    g_utf8_offset_to_pointer(candidate.c_str(), scalar) - candidate.c_str();
                candidate.insert(offset, text, size);
                (void)rimes::practice::Characters(candidate);
                s->insertion_start_ = scalar;
            } catch (...) {
                g_signal_stop_emission_by_name(b, "insert-text");
                if (s->depth_)
                    s->rejected_action_ = true;
                s->Reject();
            }
        }),
        this);
    g_signal_connect_after(
        buffer_, "insert-text",
        G_CALLBACK(+[](GtkTextBuffer *, GtkTextIter *at, gchar *, gint, gpointer data) {
            auto *s = static_cast<PracticeEditor *>(data);
            if (s->suppressed_)
                return;
            try {
                s->insertion_ = rimes::practice::InsertionRange(s->Text(), s->insertion_start_,
                                                                gtk_text_iter_get_offset(at) -
                                                                    s->insertion_start_);
            } catch (...) {
                s->Reject();
            }
            s->dirty_ = true;
            s->Publish();
        }),
        this);
    g_signal_connect(buffer_, "delete-range",
                     G_CALLBACK(+[](GtkTextBuffer *b, GtkTextIter *, GtkTextIter *, gpointer data) {
                         auto *s = static_cast<PracticeEditor *>(data);
                         if (!s->suppressed_ && !s->enabled_)
                             g_signal_stop_emission_by_name(b, "delete-range");
                     }),
                     this);
    g_signal_connect_after(
        buffer_, "delete-range",
        G_CALLBACK(+[](GtkTextBuffer *, GtkTextIter *, GtkTextIter *, gpointer data) {
            auto *s = static_cast<PracticeEditor *>(data);
            if (s->suppressed_)
                return;
            s->dirty_ = true;
            s->Publish();
        }),
        this);
    g_signal_connect(view_, "paste-clipboard", G_CALLBACK(+[](GtkTextView *v, gpointer data) {
                         g_signal_stop_emission_by_name(v, "paste-clipboard");
                         static_cast<PracticeEditor *>(data)->Reject();
                     }),
                     this);
    g_signal_connect(view_, "button-press-event",
                     G_CALLBACK(+[](GtkWidget *, GdkEventButton *e, gpointer data) -> gboolean {
                         if (e->button != 2)
                             return FALSE;
                         static_cast<PracticeEditor *>(data)->Reject();
                         return TRUE;
                     }),
                     this);
    g_signal_connect(view_, "focus-out-event",
                     G_CALLBACK(+[](GtkWidget *, GdkEvent *, gpointer data) -> gboolean {
                         auto *s = static_cast<PracticeEditor *>(data);
                         if (s->enabled_ && s->before_blur)
                             s->before_blur();
                         return FALSE;
                     }),
                     this);
    g_signal_connect_after(view_, "focus-out-event",
                           G_CALLBACK(+[](GtkWidget *, GdkEvent *, gpointer data) -> gboolean {
                               auto *s = static_cast<PracticeEditor *>(data);
                               s->down_.clear();
                               if (s->enabled_ && s->blur)
                                   s->blur();
                               return FALSE;
                           }),
                           this);
}
PracticeEditor::~PracticeEditor() {
    g_signal_handlers_disconnect_by_data(view_, this);
    g_signal_handlers_disconnect_by_data(buffer_, this);
    gtk_widget_destroy(view_);
    g_object_unref(view_);
    g_object_unref(buffer_);
}
std::string PracticeEditor::Text() const {
    GtkTextIter a, b;
    gtk_text_buffer_get_bounds(buffer_, &a, &b);
    auto *text = gtk_text_buffer_get_text(buffer_, &a, &b, FALSE);
    std::string result(text);
    g_free(text);
    return result;
}
void PracticeEditor::Enable(bool enabled) {
    enabled_ = enabled;
    gtk_text_view_set_editable(GTK_TEXT_VIEW(view_), enabled);
}
void PracticeEditor::PrepareInputContext() {
    // GTK does not focus its IM context for a read-only text view. Keep our
    // key/insert guards closed while letting GTK establish the native IC.
    enabled_ = false;
    gtk_text_view_set_editable(GTK_TEXT_VIEW(view_), TRUE);
}
void PracticeEditor::Reset(const std::string &text) {
    suppressed_ = true;
    gtk_text_view_reset_im_context(GTK_TEXT_VIEW(view_));
    gtk_text_buffer_set_text(buffer_, text.c_str(), text.size());
    suppressed_ = false;
    dirty_ = composing_ = false;
    LayoutTrack();
    insertion_.reset();
    down_.clear();
    seen_.clear();
    depth_ = 0;
}
void PracticeEditor::Source(const std::string& text, const Json& states, bool chinese) {
    track_ = true;
    const bool changed = source_ != text || chinese_ != chinese;
    source_ = text; states_ = states; chinese_ = chinese;
    gtk_text_view_set_left_margin(GTK_TEXT_VIEW(view_), 19 + (chinese_ ? 56 : 0));
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view_), GTK_WRAP_NONE);
    gtk_text_view_set_pixels_above_lines(GTK_TEXT_VIEW(view_), 32);
    gtk_text_view_set_pixels_below_lines(GTK_TEXT_VIEW(view_), 14);
    if (changed) LayoutTrack();
    gtk_widget_queue_draw(view_);
}
void PracticeEditor::LayoutTrack() {
    if (!track_ || composing_ || formatting_) return;
    namespace mat = rimes::practice::materials;
    formatting_ = true;
    const bool old_suppressed = suppressed_;
    try {
        rows_ = mat::TrackRows(source_, columns_, chinese_ ? 2 : 0);
        const auto before = Text();
        const auto typed = mat::Characters(mat::ScoredText(before));
        GtkTextIter insert, bound;
        gtk_text_buffer_get_iter_at_mark(buffer_, &insert, gtk_text_buffer_get_insert(buffer_));
        gtk_text_buffer_get_iter_at_mark(buffer_, &bound, gtk_text_buffer_get_selection_bound(buffer_));
        auto logical = [&](GtkTextIter at) {
            GtkTextIter begin; gtk_text_buffer_get_start_iter(buffer_, &begin);
            auto* prefix = gtk_text_buffer_get_text(buffer_, &begin, &at, FALSE);
            const auto count = mat::Characters(mat::ScoredText(prefix)).size(); g_free(prefix); return count;
        };
        const auto caret = logical(insert), selection = logical(bound);
        std::string formatted; std::size_t offset = 0, row = 0;
        std::vector<int> indents;
        do {
            const auto count = row < rows_.size() ? rows_[row].length : static_cast<std::size_t>(columns_);
            indents.push_back(row < rows_.size() ? rows_[row].indent : 0);
            const auto take = std::min(count, typed.size() - offset);
            for (std::size_t i = 0; i < take; ++i) formatted += typed[offset + i];
            offset += take; ++row;
            if (offset < typed.size() || (offset == typed.size() && take == count && row < rows_.size())) formatted += '\n';
            else break;
        } while (row < 20000);
        suppressed_ = true;
        if (formatted != before) gtk_text_buffer_set_text(buffer_, formatted.c_str(), static_cast<gint>(formatted.size()));
        auto* table = gtk_text_buffer_get_tag_table(buffer_);
        auto* font = gtk_text_tag_table_lookup(table, "track-font");
        if (!font) font = gtk_text_buffer_create_tag(buffer_, "track-font", "font", "Noto Sans CJK SC 16.5", nullptr);
        GtkTextIter begin, end; gtk_text_buffer_get_bounds(buffer_, &begin, &end);
        gtk_text_buffer_apply_tag(buffer_, font, &begin, &end);
        int character = 0; std::size_t line = 0;
        auto* layout = gtk_widget_create_pango_layout(view_, "");
        auto* description = pango_font_description_from_string("Noto Sans CJK SC 16.5");
        pango_layout_set_font_description(layout, description); pango_font_description_free(description);
        for (const auto& c : mat::Characters(formatted)) {
            const int count = static_cast<int>(g_utf8_strlen(c.c_str(), c.size()));
            GtkTextIter a, b; gtk_text_buffer_get_iter_at_offset(buffer_, &a, character); gtk_text_buffer_get_iter_at_offset(buffer_, &b, character + count);
            const auto indent = indents[std::min(line, indents.size() - 1)];
            const auto name = std::string("track-indent-") + std::to_string(indent);
            auto* tag = gtk_text_tag_table_lookup(table, name.c_str());
            if (!tag) tag = gtk_text_buffer_create_tag(buffer_, name.c_str(), "left-margin", 19 + indent * 28, nullptr);
            gtk_text_buffer_apply_tag(buffer_, tag, &a, &b);
            if (c == "\n") ++line;
            else {
                pango_layout_set_text(layout, c.c_str(), static_cast<int>(c.size())); int width = 0;
                pango_layout_get_pixel_size(layout, &width, nullptr);
                const auto spacing = std::clamp((28 - width) * PANGO_SCALE, -32000, 32000);
                const auto key = std::string("track-spacing-") + std::to_string(spacing);
                auto* spacing_tag = gtk_text_tag_table_lookup(table, key.c_str());
                if (!spacing_tag) spacing_tag = gtk_text_buffer_create_tag(buffer_, key.c_str(), "letter-spacing", spacing, nullptr);
                gtk_text_buffer_apply_tag(buffer_, spacing_tag, &a, &b);
            }
            character += count;
        }
        g_object_unref(layout);
        auto physical = [&](std::size_t wanted) {
            int result = 0; std::size_t seen = 0;
            for (const auto& c : mat::Characters(formatted)) {
                if (c != "\n" && seen == wanted) break;
                result += static_cast<int>(g_utf8_strlen(c.c_str(), c.size())); if (c != "\n") ++seen;
            }
            return result;
        };
        gtk_text_buffer_get_iter_at_offset(buffer_, &insert, physical(caret));
        gtk_text_buffer_get_iter_at_offset(buffer_, &bound, physical(selection));
        gtk_text_buffer_select_range(buffer_, &insert, &bound);
        suppressed_ = old_suppressed;
    } catch (const std::exception& error) { g_warning("Typing track: %s", error.what()); }
    suppressed_ = old_suppressed;
    formatting_ = false;
    const int lines = gtk_text_buffer_get_line_count(buffer_);
    gtk_text_view_set_bottom_margin(GTK_TEXT_VIEW(view_), 24 + std::max(0, static_cast<int>(rows_.size()) - lines) * 78);
    gtk_widget_queue_draw(view_);
}
void PracticeEditor::DrawTrack(cairo_t* cr) {
    if (!track_) return;
    auto* view = GTK_TEXT_VIEW(view_);
    int x = 0, top = 0;
    gtk_text_view_buffer_to_window_coords(view, GTK_TEXT_WINDOW_WIDGET, 0, 0, &x, &top);
    auto* layout = gtk_widget_create_pango_layout(view_, "");
    auto* font = pango_font_description_from_string("Noto Sans CJK SC 16.5");
    pango_layout_set_font_description(layout, font); pango_font_description_free(font);
    const auto height = gtk_widget_get_allocated_height(view_);
    GtkTextIter first; gtk_text_buffer_get_start_iter(buffer_, &first);
    GdkRectangle initial{}; gtk_text_view_get_iter_location(view, &first, &initial);
    const int line_count = gtk_text_buffer_get_line_count(buffer_);
    const int pitch = std::max(1, initial.height) + 46;
    for (std::size_t row = 0; row < rows_.size(); ++row) {
        int source_y = initial.y + static_cast<int>(row) * pitch - 32;
        if (row < static_cast<std::size_t>(line_count)) {
            GtkTextIter at; gtk_text_buffer_get_iter_at_line(buffer_, &at, static_cast<int>(row));
            GdkRectangle location{}; gtk_text_view_get_iter_location(view, &at, &location); source_y = location.y - 32;
        }
        const auto y = top + source_y;
        if (y + 28 < 0 || y > height) continue;
        const auto& source = rows_[row]; const auto chars = rimes::practice::materials::Characters(source.text);
        for (std::size_t i = 0; i < chars.size(); ++i) {
            const auto index = source.start + i;
            const auto state = index < states_.size() ? states_[index].get<int>() : 0;
            GdkRGBA color{}; gtk_style_context_get_color(gtk_widget_get_style_context(view_), GTK_STATE_FLAG_NORMAL, &color);
            if (state == 1) gdk_rgba_parse(&color, "#24945b"); else if (state >= 2) gdk_rgba_parse(&color, "#d45151"); else color.alpha *= .65;
            const auto cell_x = x + 19 + (source.indent + static_cast<int>(i)) * 28;
            auto border = color; border.alpha = .12; gdk_cairo_set_source_rgba(cr, &border); cairo_set_line_width(cr, .5);
            cairo_rectangle(cr, cell_x, y, 28, 28); cairo_rectangle(cr, cell_x, y + 32, 28, 28); cairo_stroke(cr);
            gdk_cairo_set_source_rgba(cr, &color);
            pango_layout_set_text(layout, chars[i].c_str(), static_cast<int>(chars[i].size())); int width = 0;
            pango_layout_get_pixel_size(layout, &width, nullptr);
            cairo_move_to(cr, cell_x + (28 - width) / 2., y);
            pango_cairo_show_layout(cr, layout);
        }
    }
    g_object_unref(layout);
}
void PracticeEditor::Reject() {
    if (enabled_ && assistance)
        assistance();
}
void PracticeEditor::Publish() {
    if (suppressed_ || !enabled_ || depth_ || composing_ || !dirty_)
        return;
    const auto range = insertion_;
    insertion_.reset();
    dirty_ = false;
    if (commit)
        commit(Text(), range);
    LayoutTrack();
}
} // namespace rimes::desktop
