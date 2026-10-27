package org.scholay.rimes.android;

import android.app.Instrumentation;
import android.content.Context;
import android.content.SharedPreferences;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

/** Production preference transitions in an isolated store; no IME, JNI or scheme imports. */
final class KeyboardSettingsLayoutContract {
    private final SharedPreferences preferences;
    private final KeyboardSettings settings;
    private int checks;

    private KeyboardSettingsLayoutContract(SharedPreferences preferences) {
        this.preferences=preferences;
        settings=new KeyboardSettings(preferences);
    }

    static int run(Instrumentation instrumentation) throws Exception {
        Context context=instrumentation.getTargetContext();
        String name="layout-contract-"+UUID.randomUUID();
        AtomicReference<Throwable> failure=new AtomicReference<>();
        int[] result={0};
        instrumentation.runOnMainSync(() -> {
            try {
                KeyboardSettingsLayoutContract test=new KeyboardSettingsLayoutContract(
                        context.getSharedPreferences(name,Context.MODE_PRIVATE));
                test.transitions();
                test.atomicNotifications();
                test.legacyProjectionAndEscape();
                test.independentOrthogonalSchemes();
                test.assistantLibrary();
                result[0]=test.checks;
            } catch(Throwable error) { failure.set(error); }
            finally { context.deleteSharedPreferences(name); }
        });
        Throwable error=failure.get();
        if(error instanceof Exception) throw (Exception)error;
        if(error instanceof Error) throw (Error)error;
        return result[0];
    }

    private void check(boolean value,String label) {
        checks++;
        if(!value) throw new AssertionError(label);
    }
    private void pair(String schema,String layout,String label) {
        KeyboardSettings.Snapshot selected=settings.snapshot();
        check(schema.equals(selected.schema) && layout.equals(selected.layout),label+" projected pair");
        check(schema.equals(preferences.getString(KeyboardSettings.KEY_SCHEMA,""))
                && layout.equals(preferences.getString(KeyboardSettings.KEY_LAYOUT,"")),label+" stored pair");
        // A new model restores preferences; full process/Activity persistence belongs to AppSettingsContract.
        KeyboardSettings.Snapshot restored=new KeyboardSettings(preferences).snapshot();
        check(schema.equals(restored.schema) && layout.equals(restored.layout),label+" new model restores pair");
    }

    private void transitions() {
        settings.setLearningEnabled(false);
        settings.setAiMockEnabled(false);
        settings.setTranslationDirection("en-zh");
        settings.setTheme(KeyboardSettings.themeValues().get(1));
        settings.setLayout("nineKey");
        pair("rimes_pinyin","nineKey","select nine-key");
        settings.setLayout("qwerty");
        pair("rimes_pinyin","qwerty","explicit nine-key to 26-key");

        for(String schema:new String[]{"rimes_ziranma","rimes_wubi"}) {
            settings.setLayout("nineKey");
            settings.setSchema(schema);
            pair(schema,"qwerty","nine-key to "+schema);
            settings.setSchema("rimes_pinyin");
            pair("rimes_pinyin","qwerty","regular scheme retains selected 26-key");
            settings.setSchema(schema);
            settings.setLayout("orthogonal");
            pair(schema,"orthogonal","chord keeps ordinary scheme");
            settings.setLayout("qwerty");
            pair(schema,"qwerty","chord to 26-key restores ordinary scheme");
        }
        KeyboardSettings.Snapshot saved=new KeyboardSettings(preferences).snapshot();
        check(!saved.learning && !saved.aiMockEnabled,"layout changes preserve learning and AI settings");
        check("en-zh".equals(saved.translationDirection)
                && KeyboardSettings.themeValues().get(1).equals(saved.theme),"layout changes preserve direction and theme");
    }

    private void atomicNotifications() {
        List<String> observed=new ArrayList<>();
        SharedPreferences.OnSharedPreferenceChangeListener listener=(changed,key) -> {
            if(!KeyboardSettings.KEY_SCHEMA.equals(key) && !KeyboardSettings.KEY_LAYOUT.equals(key)) return;
            KeyboardSettings.Snapshot pair=settings.snapshot();
            String rawSchema=changed.getString(KeyboardSettings.KEY_SCHEMA,"");
            String rawLayout=changed.getString(KeyboardSettings.KEY_LAYOUT,"");
            check(pair.schema.equals(rawSchema) && pair.layout.equals(rawLayout),"notification sees complete persisted pair");
            check(!"nineKey".equals(rawLayout) || "rimes_pinyin".equals(rawSchema),"notification never sees non-Pinyin nine-key");
            observed.add(rawSchema+"/"+rawLayout);
        };
        preferences.registerOnSharedPreferenceChangeListener(listener);
        try {
            settings.setLayout("nineKey");
            check(!observed.isEmpty(),"layout selection emits preference notifications");
            check(observed.stream().allMatch("rimes_pinyin/nineKey"::equals),"all nine-key notifications share final pair");
            observed.clear();
            settings.setSchema("rimes_wubi");
            check(!observed.isEmpty(),"scheme selection emits preference notifications");
            check(observed.stream().allMatch("rimes_wubi/qwerty"::equals),"all scheme notifications share final pair");
        } finally { preferences.unregisterOnSharedPreferenceChangeListener(listener); }
    }

    private void seed(Object schema,Object layout) {
        SharedPreferences.Editor editor=preferences.edit().clear().putBoolean("layout_schema_v120",true);
        if(schema instanceof String) editor.putString(KeyboardSettings.KEY_SCHEMA,(String)schema);
        else editor.putInt(KeyboardSettings.KEY_SCHEMA,7);
        if(layout instanceof String) editor.putString(KeyboardSettings.KEY_LAYOUT,(String)layout);
        else editor.putBoolean(KeyboardSettings.KEY_LAYOUT,true);
        check(editor.commit(),"synthetic legacy preferences stored");
    }
    private void readOnlyProjection(String schema,String layout,String label) {
        Map<String,?> before=new HashMap<>(preferences.getAll());
        KeyboardSettings.Snapshot projected=new KeyboardSettings(preferences).snapshot();
        check(schema.equals(projected.schema) && layout.equals(projected.layout),label+" safe projection");
        check(before.equals(preferences.getAll()),label+" read never rewrites raw preferences");
    }
    private void legacyProjectionAndEscape() {
        seed("rimes_wubi","nineKey");
        readOnlyProjection("rimes_wubi","qwerty","incompatible legacy scheme/layout");
        settings.setLayout("qwerty");
        pair("rimes_wubi","qwerty","legacy pair explicitly returns to 26-key");

        // A raw unknown ID is not an imported scheme. Verify it cannot prevent explicit layout recovery.
        seed("wanxiang","nineKey");
        Map<String,?> before=new HashMap<>(preferences.getAll());
        check("rimes_pinyin".equals(settings.getSchema()),"unrecognized stored ID uses bundled fallback, not import");
        check(before.equals(preferences.getAll()),"unrecognized ID projection preserves raw preferences");
        settings.setLayout("qwerty");
        pair("rimes_pinyin","qwerty","unrecognized stored ID cannot lock nine-key");

        seed(7,true);
        readOnlyProjection("rimes_pinyin","qwerty","wrong-type legacy preferences");
        settings.setLayout("qwerty");
        pair("rimes_pinyin","qwerty","wrong-type preferences explicitly recover");
    }
    private void independentOrthogonalSchemes() {
        settings.setSchema("rimes_wubi");settings.setLayout("orthogonal");settings.setSchema("rimes_pinyin");
        pair("rimes_pinyin","orthogonal","ordinary scheme keeps orthogonal geometry");
        check("rimes_pinyin".equals(settings.builtInRuntimeSchema(true)),"ordinary grid never silently switches to Natural Code");
        settings.setSchema("isaac2026");pair("isaac2026","orthogonal","chord scheme selects its grid");
        check("rimes_ziranma".equals(settings.builtInRuntimeSchema(false)),"disabled chord plugin retains the underlying Natural Code typing path");
        preferences.edit().remove("layout_schema_v120").putString("schema","rimes_pinyin").putString("layout","orthogonal").commit();
        KeyboardSettings migrated=new KeyboardSettings(preferences);
        check("isaac2026".equals(migrated.getSchema()),"upgrade preserves the old chord behavior");
        migrated.setSchema("rimes_wubi");
        check("rimes_wubi".equals(new KeyboardSettings(preferences).getSchema()),"migration runs once and does not overwrite a later ordinary choice");
    }
    private void assistantLibrary() {
        AssistantSettings store=new AssistantSettings(preferences);
        check(store.snapshot().entrance.equals(AssistantSettings.BUILT_INS),"old users retain all five built-in shortcuts");
        AssistantSettings.Preset first=AssistantSettings.create("Reply","Keep the meaning, use a gentle tone.","Write a reply");
        store.save(first);store.entrance(first.id,true);store.move(first.id,-1);
        check(new AssistantSettings(preferences).snapshot().preset(first.id)!=null,"custom assistant persists through a new store");
        String before=store.revision();
        store.save(new AssistantSettings.Preset(first.id,"Renamed","New instruction",""));
        check(!before.equals(store.revision()),"editing changes the frozen request authority");
        boolean rejected=false;try { store.save(new AssistantSettings.Preset(first.id,"X",new String(new char[4001]).replace((char)0,'x'),"")); } catch(IllegalArgumentException expected) { rejected=true; }
        check(rejected && "New instruction".equals(store.instruction(first.id)),"oversized instructions do not replace the old preset");
        store.remove(first.id);check(!store.snapshot().entrance.contains(first.id),"removing an assistant retires its shortcut");
    }

}
