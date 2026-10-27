package org.scholay.rimes.android;

import android.content.Context;
import android.view.Gravity;
import android.view.View;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;

/** iOS-sized plugin entries occupying the idle candidate slot; actions belong to the service. */
final class PluginShortcutBar extends HorizontalScrollView {
    interface Listener {
        void onPluginTap(String id);
        void onPluginLongPress(String id);
    }

    private static final String[] IDS={"translate","ask","polish","poem","art"};
    private static final String[] LABELS={"翻译","快问","润色","作诗","画画"};
    private static final KeyboardIcon[] ICONS={KeyboardIcon.TRANSLATE,KeyboardIcon.CHAT_QUESTION,
            KeyboardIcon.MAGIC_WAND,KeyboardIcon.BOOK,KeyboardIcon.GRID_9};
    private final java.util.List<KeyButton> buttons=new java.util.ArrayList<>();
    private final java.util.List<String> entries=new java.util.ArrayList<>();
    private final LinearLayout row;
    private final Listener listener;
    private final AssistantSettings assistants;
    private String revision;

    PluginShortcutBar(Context context,KeyboardTheme theme,Listener listener) {
        super(context);
        if(listener==null) throw new IllegalArgumentException("Plugin listener is required");
        setFillViewport(true); setHorizontalScrollBarEnabled(false); setOverScrollMode(View.OVER_SCROLL_NEVER);
        setPadding(0,0,0,0); setMinimumHeight(dp(32));
        this.listener=listener; assistants=new AssistantSettings(context);
        row=new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL); row.setGravity(Gravity.CENTER);
        addView(row,new HorizontalScrollView.LayoutParams(LayoutParams.WRAP_CONTENT,dp(32)));
        rebuild(theme);
    }
    private void rebuild(KeyboardTheme theme) {
        revision=assistants.revision();
        String displayedRevision=revision;
        row.removeAllViews(); buttons.clear(); entries.clear();
        AssistantSettings.Snapshot library=assistants.snapshot(); entries.addAll(library.entrance);
        for(int i=0;i<entries.size();i++) {
            String id=entries.get(i); int builtIn=java.util.Arrays.asList(IDS).indexOf(id);
            AssistantSettings.Preset preset=library.preset(id);
            String label=builtIn>=0?LABELS[builtIn]:preset==null?"":preset.name;
            KeyButton button=new KeyButton(getContext());
            button.setText(label); button.setContentDescription("Buffer 插件："+label);
            button.fontStyle(false,13,true); button.appearance(true,true,true); button.shortcut(true);
            button.icon(builtIn>=0?ICONS[builtIn]:KeyboardIcon.CHAT_QUESTION,12,true); button.theme(theme);
            button.setOnClickListener(view -> { if(button.isEnabled() && displayedRevision.equals(assistants.revision())) listener.onPluginTap(id); });
            button.setOnLongClickListener(view -> {
                if(button.isEnabled() && displayedRevision.equals(assistants.revision())) listener.onPluginLongPress(id);
                return true;
            });
            LinearLayout.LayoutParams cell=new LinearLayout.LayoutParams(dp(builtIn>=0?68:96),dp(30));
            if(i<entries.size()-1) cell.rightMargin=dp(6);
            row.addView(button,cell); buttons.add(button);
        }
    }

    /** Keeps entries and scroll position stable while updating selection, availability and colors. */
    void render(KeyboardTheme theme,String selectedID,boolean enabled) {
        render(theme,selectedID,enabled,id -> true);
    }
    void render(KeyboardTheme theme,String selectedID,boolean available,java.util.function.Predicate<String> installed) {
        if(!assistants.revision().equals(revision)) rebuild(theme);
        for(int i=0;i<buttons.size();i++) {
            KeyButton button=buttons.get(i);
            boolean enabled=available && installed.test(entries.get(i));
            button.theme(theme);
            boolean selected=entries.get(i).equals(selectedID);
            if(button.isSelected()!=selected) button.setSelected(selected);
            if(button.isEnabled()!=enabled) {
                if(!enabled) { button.cancelLongPress(); button.setPressed(false); }
                button.setEnabled(enabled);
            }
        }
    }

    private int dp(float value) { return Math.round(value*getResources().getDisplayMetrics().density); }
}
