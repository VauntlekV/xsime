package org.scholay.rimes.android;

import android.content.Context;
import android.content.SharedPreferences;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;

/** User-authored assistant instructions. The keyboard consumes a frozen snapshot. */
final class AssistantSettings {
    static final String KEY="assistant_library_v1";
    static final List<String> BUILT_INS=java.util.Collections.unmodifiableList(Arrays.asList("translate","ask","polish","poem","art"));
    static final int MAX_PRESETS=24, MAX_INSTRUCTION_BYTES=4000;
    private final SharedPreferences preferences;
    static final class Preset {
        final String id,name,instruction,placeholder;
        Preset(String id,String name,String instruction,String placeholder) {
            this.id=id; this.name=name.trim(); this.instruction=instruction.trim(); this.placeholder=placeholder.trim();
        }
        boolean valid() {
            return isPreset(id) && !name.isEmpty() && name.length()<=80 && !instruction.isEmpty()
                    && instruction.getBytes(StandardCharsets.UTF_8).length<=MAX_INSTRUCTION_BYTES && placeholder.length()<=256;
        }
        JSONObject json() throws org.json.JSONException {
            return new JSONObject().put("id",id).put("name",name).put("instruction",instruction).put("placeholder",placeholder);
        }
    }
    static final class Snapshot {
        final List<Preset> presets;
        final List<String> entrance;
        Snapshot(List<Preset> presets,List<String> entrance) {
            this.presets=java.util.Collections.unmodifiableList(presets);
            this.entrance=java.util.Collections.unmodifiableList(entrance);
        }
        Preset preset(String id) { for(Preset p:presets) if(p.id.equals(id)) return p; return null; }
    }
    AssistantSettings(Context context) { this(context.getSharedPreferences(KeyboardSettings.PREFERENCES_NAME,Context.MODE_PRIVATE)); }
    AssistantSettings(SharedPreferences preferences) { this.preferences=preferences; }
    static boolean isPreset(String id) {
        return id!=null && id.matches("preset\\.[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
    }
    static String basePlugin(String id) { return isPreset(id)?"ask":id; }
    Snapshot snapshot() {
        ArrayList<Preset> presets=new ArrayList<>();
        LinkedHashSet<String> entries=new LinkedHashSet<>();
        try {
            String raw=preferences.getString(KEY,"{}");
            if(raw==null || raw.getBytes(StandardCharsets.UTF_8).length>131072) return new Snapshot(presets,new ArrayList<>(BUILT_INS));
            JSONObject value=new JSONObject(raw);
            JSONArray saved=value.optJSONArray("presets");
            if(saved!=null) for(int i=0;i<Math.min(saved.length(),MAX_PRESETS);i++) {
                JSONObject p=saved.optJSONObject(i); if(p==null) continue;
                Preset preset=new Preset(p.optString("id"),p.optString("name"),p.optString("instruction"),p.optString("placeholder"));
                if(preset.valid() && presets.stream().noneMatch(x -> x.id.equals(preset.id))) presets.add(preset);
            }
            JSONArray selected=value.optJSONArray("entrance");
            if(selected==null) entries.addAll(BUILT_INS);
            else for(int i=0;i<Math.min(selected.length(),MAX_PRESETS+BUILT_INS.size());i++) {
                String id=selected.optString(i);
                if(BUILT_INS.contains(id) || presets.stream().anyMatch(p -> p.id.equals(id))) entries.add(id);
            }
        } catch(Exception ignored) { entries.addAll(BUILT_INS); }
        return new Snapshot(presets,new ArrayList<>(entries));
    }
    String instruction(String id) { Preset p=snapshot().preset(id); return p==null?null:p.instruction; }
    String revision() {
        try {
            byte[] digest=MessageDigest.getInstance("SHA-256").digest(preferences.getString(KEY,"{}").getBytes(StandardCharsets.UTF_8));
            StringBuilder text=new StringBuilder(); for(byte b:digest) text.append(String.format(java.util.Locale.ROOT,"%02x",b&255)); return text.toString();
        } catch(Exception ignored) { return "invalid"; }
    }
    synchronized void save(Preset preset) {
        if(!preset.valid()) throw new IllegalArgumentException("名称不能为空，提示词限 4000 UTF-8 字节，提示文字限 256 字。");
        Snapshot old=snapshot(); ArrayList<Preset> items=new ArrayList<>(old.presets);
        int index=-1; for(int i=0;i<items.size();i++) if(items.get(i).id.equals(preset.id)) index=i;
        if(index>=0) items.set(index,preset);
        else { if(items.size()>=MAX_PRESETS) throw new IllegalArgumentException("最多保存 24 个助手。"); items.add(preset); }
        write(items,old.entrance);
    }
    synchronized void remove(String id) {
        Snapshot old=snapshot(); ArrayList<Preset> items=new ArrayList<>(old.presets); items.removeIf(p -> p.id.equals(id));
        ArrayList<String> entries=new ArrayList<>(old.entrance); entries.remove(id); write(items,entries);
    }
    synchronized void entrance(String id,boolean enabled) {
        Snapshot old=snapshot(); if(!BUILT_INS.contains(id) && old.preset(id)==null) return;
        ArrayList<String> entries=new ArrayList<>(old.entrance); entries.remove(id); if(enabled) entries.add(id); write(old.presets,entries);
    }
    synchronized void move(String id,int delta) {
        Snapshot old=snapshot(); ArrayList<String> entries=new ArrayList<>(old.entrance); int index=entries.indexOf(id),next=index+delta;
        if(index<0 || next<0 || next>=entries.size()) return;
        java.util.Collections.swap(entries,index,next); write(old.presets,entries);
    }
    static Preset create(String name,String instruction,String placeholder) { return new Preset("preset."+UUID.randomUUID(),name,instruction,placeholder); }
    private void write(List<Preset> presets,List<String> entries) {
        try {
            JSONArray array=new JSONArray(); for(Preset p:presets) array.put(p.json());
            String raw=new JSONObject().put("version",1).put("presets",array).put("entrance",new JSONArray(entries)).toString();
            if(raw.getBytes(StandardCharsets.UTF_8).length>131072) throw new IllegalArgumentException("助手设置过大。");
            preferences.edit().putString(KEY,raw).apply();
        } catch(org.json.JSONException error) { throw new IllegalArgumentException("无法保存助手设置。",error); }
    }
}
