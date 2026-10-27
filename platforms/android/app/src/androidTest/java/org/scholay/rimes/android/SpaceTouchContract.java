package org.scholay.rimes.android;

import android.app.Instrumentation;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.widget.Button;
import java.util.ArrayList;
import java.util.concurrent.atomic.AtomicReference;
import org.scholay.rimes.core.SpaceGesture;

/** Dispatch actual Android touch streams through the native space button. */
final class SpaceTouchContract {
    static int run(Instrumentation instrumentation) {
        AtomicReference<Throwable> failure=new AtomicReference<>();
        int[] checks={0};
        instrumentation.runOnMainSync(() -> {
            try {
                Button button=new Button(instrumentation.getTargetContext());
                float density=button.getResources().getDisplayMetrics().density;
                ArrayList<SpaceGesture.Kind> actions=new ArrayList<>(); int[] clicks={0};
                button.setOnClickListener(view -> clicks[0]++);
                SpaceKeyTouch touch=new SpaceKeyTouch(button,new SpaceKeyTouch.Listener() {
                    public void begin() {}
                    public void cancel() {}
                    public void action(SpaceGesture.Kind kind,int delta) { actions.add(kind); }
                });
                long now=SystemClock.uptimeMillis();
                event(button,density,now,MotionEvent.ACTION_DOWN,10,10);
                event(button,density,now,MotionEvent.ACTION_UP,10,10);
                require(clicks[0]==1 && actions.isEmpty(),"one tap is one accessible click",checks);
                event(button,density,now,MotionEvent.ACTION_DOWN,10,10);
                event(button,density,now,MotionEvent.ACTION_MOVE,62,10);
                event(button,density,now,MotionEvent.ACTION_UP,62,10);
                require(clicks[0]==1 && actions.contains(SpaceGesture.Kind.PICK)
                        && actions.stream().filter(x -> x==SpaceGesture.Kind.CONFIRM).count()==1,
                        "candidate drag confirms once without a space",checks);
                actions.clear();
                event(button,density,now,MotionEvent.ACTION_DOWN,10,10);
                event(button,density,now,MotionEvent.ACTION_CANCEL,10,10);
                event(button,density,now,MotionEvent.ACTION_UP,10,10);
                require(clicks[0]==1 && actions.isEmpty(),"cancelled stream cannot insert",checks);
                event(button,density,now,MotionEvent.ACTION_DOWN,10,10);
                dual(button,density,now,MotionEvent.ACTION_POINTER_DOWN,10,210);
                dual(button,density,now,MotionEvent.ACTION_MOVE,70,150);
                dual(button,density,now,MotionEvent.ACTION_POINTER_UP,70,150);
                event(button,density,now,MotionEvent.ACTION_UP,70,10);
                require(actions.size()==1 && actions.get(0)==SpaceGesture.Kind.IMPORT_BUFFER && clicks[0]==1,
                        "pinch produces one explicit import without trailing taps",checks);
                actions.clear();
                event(button,density,now,MotionEvent.ACTION_DOWN,10,10);
                touch.cancel();
                event(button,density,now,MotionEvent.ACTION_MOVE,80,10);
                event(button,density,now,MotionEvent.ACTION_UP,80,10);
                require(actions.isEmpty() && clicks[0]==1,"retired button rejects stale moves and release",checks);
            } catch(Throwable error) { failure.set(error); }
        });
        if(failure.get()!=null) throw new AssertionError("Space touch contract",failure.get());
        return checks[0];
    }
    private static void require(boolean value,String label,int[] checks) {
        if(!value) throw new AssertionError(label); checks[0]++;
    }
    private static void event(Button button,float density,long time,int action,float x,float y) {
        MotionEvent event=MotionEvent.obtain(time,time+10,action,x*density,y*density,0);
        button.dispatchTouchEvent(event);event.recycle();
    }
    private static void dual(Button button,float density,long time,int action,float first,float second) {
        MotionEvent.PointerProperties[] properties=new MotionEvent.PointerProperties[2];
        MotionEvent.PointerCoords[] coords=new MotionEvent.PointerCoords[2];
        for(int i=0;i<2;i++) {
            properties[i]=new MotionEvent.PointerProperties(); properties[i].id=i;
            properties[i].toolType=MotionEvent.TOOL_TYPE_FINGER;
            coords[i]=new MotionEvent.PointerCoords(); coords[i].x=(i==0?first:second)*density;
            coords[i].y=10*density; coords[i].pressure=1;coords[i].size=1;
        }
        if(action==MotionEvent.ACTION_POINTER_DOWN || action==MotionEvent.ACTION_POINTER_UP)
            action|=1<<MotionEvent.ACTION_POINTER_INDEX_SHIFT;
        MotionEvent event=MotionEvent.obtain(time,time+20,action,2,properties,coords,0,0,1,1,0,0,android.view.InputDevice.SOURCE_TOUCHSCREEN,0);
        button.dispatchTouchEvent(event);event.recycle();
    }
}
