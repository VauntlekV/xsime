package org.scholay.rimes.android;

import android.view.MotionEvent;
import android.view.View;
import org.scholay.rimes.core.SpaceGesture;

/** Native space button accessibility remains a click; touch gestures have one owner. */
final class SpaceKeyTouch implements View.OnTouchListener {
    interface Listener { void begin(); void action(SpaceGesture.Kind kind,int delta); void cancel(); }
    private final View view; private final Listener listener; private final SpaceGesture gesture=new SpaceGesture();
    private int pointers;
    private boolean active;
    private final Runnable hold;
    SpaceKeyTouch(View view,Listener listener) { this.view=view;this.listener=listener;
        hold=() -> { if(active && pointers==1 && gesture.hold(android.os.SystemClock.uptimeMillis())) view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS); };
        view.setOnTouchListener(this); }
    void cancel() { view.removeCallbacks(hold);gesture.cancel();active=false;pointers=0;view.setPressed(false);listener.cancel(); }
    private void send(SpaceGesture.Action action) { if(action.kind!=SpaceGesture.Kind.NONE) listener.action(action.kind,action.delta); }
    @Override public boolean onTouch(View touched,MotionEvent event) {
        if(event.getActionMasked()==MotionEvent.ACTION_DOWN) {
            cancel();active=true;pointers=1;listener.begin();
            float d=view.getResources().getDisplayMetrics().density;
            gesture.begin(event.getX()/d,event.getY()/d,event.getEventTime());view.setPressed(true);view.postDelayed(hold,1000);return true;
        }
        if(!active) return true;
        float d=view.getResources().getDisplayMetrics().density;
        if(event.getActionMasked()==MotionEvent.ACTION_CANCEL) { cancel();return true; }
        if(event.getActionMasked()==MotionEvent.ACTION_POINTER_DOWN) {
            view.removeCallbacks(hold);pointers=event.getPointerCount();
            if(pointers!=2) { cancel();return true; }
            gesture.second((event.getX(0)+event.getX(1))/(2*d),(event.getY(0)+event.getY(1))/(2*d),Math.abs(event.getX(0)-event.getX(1))/d);return true;
        }
        if(event.getActionMasked()==MotionEvent.ACTION_MOVE) {
            float x=event.getX()/d,y=event.getY()/d,span=0;
            if(event.getPointerCount()==2) { x=(event.getX(0)+event.getX(1))/(2*d);y=(event.getY(0)+event.getY(1))/(2*d);span=Math.abs(event.getX(0)-event.getX(1))/d; }
            send(gesture.move(x,y,span));return true;
        }
        if(event.getActionMasked()==MotionEvent.ACTION_POINTER_UP || event.getActionMasked()==MotionEvent.ACTION_UP) {
            view.removeCallbacks(hold);SpaceGesture.Action action=gesture.end();active=false;pointers=0;view.setPressed(false);
            if(action.kind==SpaceGesture.Kind.TAP) view.performClick(); else send(action);
            listener.cancel();return true;
        }
        return true;
    }
}
