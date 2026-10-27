#pragma once
#include "desktop.hpp"
#include <optional>
#include "material_library.hpp"
#include <set>

namespace rimes::desktop {
// Call before gtk_init in settings so native key accounting precedes IM filtering.
void ConfigurePracticeInput();
class PracticeEditor {
  public:
    PracticeEditor();
    ~PracticeEditor();
    GtkWidget *Widget() const { return view_; }
    std::string Text() const;
    void Reset(const std::string &text = {});
    void Enable(bool enabled);
    void Source(const std::string& text, const Json& states = Json::array(), bool chinese = true);
    void PrepareInputContext();
    bool Composing() const { return composing_; }
    std::function<void(guint32, guint16, bool, bool, bool)> key;
    std::function<void()> composition, assistance, before_blur, blur;
    std::function<void(const std::string &, std::optional<std::pair<int, int>>)> commit;

  private:
    GtkWidget *view_;
    GtkTextBuffer *buffer_;
    bool enabled_ = false, composing_ = false, suppressed_ = false, dirty_ = false;
    unsigned depth_ = 0;
    std::string before_action_;
    bool rejected_action_ = false;
    std::set<guint16> down_;
    std::set<std::pair<guint32, guint16>> seen_;
    std::optional<std::pair<int, int>> insertion_;
    int insertion_start_ = 0;
    std::string source_;
    Json states_ = Json::array();
    int columns_ = 20;
    bool track_ = false, chinese_ = true, formatting_ = false;
    std::vector<rimes::practice::materials::TrackRow> rows_;
    void LayoutTrack();
    void DrawTrack(cairo_t* cr);
    void Publish();
    void Reject();
};
} // namespace rimes::desktop
