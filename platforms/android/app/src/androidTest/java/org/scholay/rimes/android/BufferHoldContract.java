package org.scholay.rimes.android;

import android.app.Instrumentation;
import android.app.Activity;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.widget.Button;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/** The one-second action runs on the real window's animation clock. */
final class BufferHoldContract {
    static int run(Instrumentation instrumentation) throws Exception {
        Instrumentation.ActivityMonitor monitor=instrumentation.addMonitor(SetupActivity.class.getName(),null,false);
        Activity activity=null;
        String component=instrumentation.getTargetContext().getPackageName()+"/"+SetupActivity.class.getName();
        try(android.os.ParcelFileDescriptor launch=instrumentation.getUiAutomation().executeShellCommand("am start -W -f 0x10008000 -n "+component)) {
            activity=instrumentation.waitForMonitorWithTimeout(monitor,15000);
            if(activity==null) throw new AssertionError("Buffer hold fixture did not start");
            return attached(instrumentation,activity);
        } finally {
            instrumentation.removeMonitor(monitor);
            if(activity!=null) { Activity fixture=activity;instrumentation.runOnMainSync(fixture::finish);instrumentation.waitForIdleSync(); }
        }
    }
    private static int attached(Instrumentation instrumentation,Activity activity) throws Exception {
        AtomicReference<Button> button=new AtomicReference<>();
        AtomicReference<BufferSendTouch> touch=new AtomicReference<>();
        AtomicInteger taps=new AtomicInteger(),sends=new AtomicInteger();
        try {
            instrumentation.runOnMainSync(() -> {
                Button control=new Button(activity);control.setText("Send");activity.setContentView(control);
                control.setOnClickListener(v -> taps.incrementAndGet());button.set(control);
                touch.set(new BufferSendTouch(control,value -> {},() -> sends::incrementAndGet));
            });
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> event(button.get(),MotionEvent.ACTION_DOWN));
            Thread.sleep(400);
            if(sends.get()!=0) throw new AssertionError("Full send must wait one second");
            long deadline=SystemClock.uptimeMillis()+3000;
            while(sends.get()==0 && SystemClock.uptimeMillis()<deadline) Thread.sleep(20);
            if(sends.get()!=1) throw new AssertionError("One hold sends exactly once");
            instrumentation.runOnMainSync(() -> event(button.get(),MotionEvent.ACTION_UP));
            instrumentation.waitForIdleSync();
            if(taps.get()!=0 || sends.get()!=1) throw new AssertionError("Release after hold must not send another block");
            instrumentation.runOnMainSync(() -> {
                event(button.get(),MotionEvent.ACTION_DOWN);touch.get().cancel();event(button.get(),MotionEvent.ACTION_UP);
            });
            Thread.sleep(1100);
            if(taps.get()!=0 || sends.get()!=1) throw new AssertionError("Retirement cancels pending full send");
            instrumentation.runOnMainSync(() -> {event(button.get(),MotionEvent.ACTION_DOWN);event(button.get(),MotionEvent.ACTION_UP);});
            if(taps.get()!=1 || sends.get()!=1) throw new AssertionError("Quick tap retains the ordinary block action");
            return 5;
        } finally { instrumentation.runOnMainSync(() -> { if(touch.get()!=null) touch.get().cancel(); }); }
    }
    private static void event(Button button,int action) {
        long now=SystemClock.uptimeMillis();
        MotionEvent event=MotionEvent.obtain(now,now,action,button.getWidth()/2f,button.getHeight()/2f,0);
        button.dispatchTouchEvent(event);event.recycle();
    }
}
