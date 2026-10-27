package org.scholay.rimes.android;

import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import java.util.function.Consumer;
import java.util.function.Supplier;

/** One-second full-send hold; the captured command owns its field and draft. */
final class BufferSendTouch implements View.OnTouchListener, View.OnAttachStateChangeListener {
    private final View button;
    private final Consumer<Float> progress;
    private final Supplier<Runnable> capture;
    private boolean active, fired;
    private long began;
    private Runnable command;
    private final Runnable frame=new Runnable() {
        @Override public void run() {
            if(!active) return;
            if(!button.isShown() || !button.isEnabled()) { cancel(); return; }
            float value=Math.min(1,(SystemClock.uptimeMillis()-began)/1000f);
            progress.accept(value);
            if(value>=1) {
                fired=true;
                Runnable action=command;command=null;
                if(action!=null) action.run();
                progress.accept(0f);
            } else button.postOnAnimation(this);
        }
    };
    BufferSendTouch(View button,Consumer<Float> progress,Supplier<Runnable> capture) {
        this.button=button;this.progress=progress;this.capture=capture;
        button.setOnTouchListener(this);button.addOnAttachStateChangeListener(this);
    }
    void cancel() { active=false;command=null;button.removeCallbacks(frame);button.setPressed(false);progress.accept(0f); }
    @Override public boolean onTouch(View view,MotionEvent event) {
        if(event.getActionMasked()==MotionEvent.ACTION_DOWN) {
            cancel();active=true;fired=false;began=SystemClock.uptimeMillis();command=capture.get();
            view.setPressed(true);view.postOnAnimation(frame);return true;
        }
        if(!active) return true;
        if(event.getActionMasked()==MotionEvent.ACTION_CANCEL || event.getActionMasked()==MotionEvent.ACTION_POINTER_DOWN) {cancel();return true;}
        if(event.getActionMasked()==MotionEvent.ACTION_MOVE) {
            float slop=12*view.getResources().getDisplayMetrics().density;
            if(event.getX() < -slop || event.getY() < -slop || event.getX() > view.getWidth()+slop || event.getY() > view.getHeight()+slop) cancel();
            return true;
        }
        if(event.getActionMasked()==MotionEvent.ACTION_UP) {
            boolean tap=!fired;cancel();if(tap) view.performClick();return true;
        }
        return true;
    }
    public void onViewAttachedToWindow(View view) {}
    public void onViewDetachedFromWindow(View view) {cancel();}
}
