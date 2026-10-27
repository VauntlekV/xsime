package org.scholay.rimes.core;

/** Space owns one touch stream. Every stream resolves to a tap, a gesture, or cancellation. */
public final class SpaceGesture {
    public enum Kind { NONE, TAP, PICK, PAGE, CONFIRM, CURSOR, OPEN_BUFFER, CLOSE_BUFFER, IMPORT_BUFFER }
    public static final class Action {
        public final Kind kind; public final int delta;
        Action(Kind kind,int delta) { this.kind=kind; this.delta=delta; }
    }
    private static final Action NONE=new Action(Kind.NONE,0);
    private boolean active,dual,moved,cursor,finished;
    private float x,y,lastX,lastY,span;
    private long began;
    private int axis;
    public void begin(float x,float y,long now) {
        active=true;dual=false;moved=false;cursor=false;finished=false;axis=0;
        this.x=lastX=x;this.y=lastY=y;began=now;
    }
    public void second(float centerX,float centerY,float span) {
        if(!active) return;
        dual=true;cursor=false;moved=true;axis=0;x=lastX=centerX;y=lastY=centerY;this.span=span;
    }
    public boolean hold(long now) {
        if(!active || dual || moved || now-began<1000) return false;
        cursor=true;return true;
    }
    public Action move(float currentX,float currentY,float currentSpan) {
        if(!active || finished) return NONE;
        float dx=currentX-x,dy=currentY-y;
        if(dual) {
            if(span>=48 && currentSpan<span*0.6f) { finished=true;return new Action(Kind.IMPORT_BUFFER,0); }
            if(Math.abs(dy)>=24) { finished=true;return new Action(dy<0?Kind.OPEN_BUFFER:Kind.CLOSE_BUFFER,0); }
            return NONE;
        }
        if(cursor) {
            int steps=(int)((currentX-lastX)/12);
            if(steps!=0) { lastX+=steps*12;return new Action(Kind.CURSOR,steps); }
            return NONE;
        }
        if(axis==0) {
            if(Math.max(Math.abs(dx),Math.abs(dy))<12) return NONE;
            moved=true;axis=Math.abs(dx)>=Math.abs(dy)?1:2;
        }
        int steps=(int)((axis==1?currentX-lastX:currentY-lastY)/24);
        if(steps==0) return NONE;
        if(axis==1) lastX+=steps*24; else lastY+=steps*24;
        return new Action(axis==1?Kind.PICK:Kind.PAGE,steps);
    }
    public Action end() {
        if(!active) return NONE;
        active=false;
        return dual || cursor || finished?NONE:new Action(moved?Kind.CONFIRM:Kind.TAP,0);
    }
    public void cancel() { active=false;finished=true; }
}
