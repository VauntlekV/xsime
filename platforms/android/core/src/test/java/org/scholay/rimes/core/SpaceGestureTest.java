package org.scholay.rimes.core;
import org.junit.Test;
import static org.junit.Assert.*;

public class SpaceGestureTest {
    @Test public void aTapAndCancelledStreamDoNotBecomeGestures() {
        SpaceGesture g=new SpaceGesture();g.begin(80,20,0);
        assertEquals(SpaceGesture.Kind.TAP,g.end().kind);
        assertEquals(SpaceGesture.Kind.NONE,g.end().kind);
        g.begin(80,20,0);g.cancel();assertEquals(SpaceGesture.Kind.NONE,g.end().kind);
    }
    @Test public void dragPicksButOnlyReleaseConfirmsAndHoldDoesNotStealIt() {
        SpaceGesture g=new SpaceGesture();g.begin(80,20,0);
        SpaceGesture.Action action=g.move(130,20,0);
        assertEquals(SpaceGesture.Kind.PICK,action.kind);assertEquals(2,action.delta);
        assertFalse(g.hold(1500));assertEquals(SpaceGesture.Kind.CONFIRM,g.end().kind);
        g.begin(80,20,0);assertFalse(g.hold(999));assertTrue(g.hold(1000));
        assertEquals(SpaceGesture.Kind.CURSOR,g.move(105,20,0).kind);
        assertEquals(SpaceGesture.Kind.NONE,g.end().kind);
    }
    @Test public void twoFingersChooseExactlyOneActionAndNeverInsertASpace() {
        SpaceGesture g=new SpaceGesture();g.begin(20,30,0);g.second(100,30,160);
        assertEquals(SpaceGesture.Kind.IMPORT_BUFFER,g.move(100,30,70).kind);
        assertEquals(SpaceGesture.Kind.NONE,g.move(100,0,60).kind);
        assertEquals(SpaceGesture.Kind.NONE,g.end().kind);
        g.begin(20,30,0);g.second(100,30,160);
        assertEquals(SpaceGesture.Kind.OPEN_BUFFER,g.move(100,0,160).kind);
        assertEquals(SpaceGesture.Kind.NONE,g.end().kind);
        g.begin(20,30,0);g.second(100,30,160);
        assertEquals(SpaceGesture.Kind.CLOSE_BUFFER,g.move(100,60,160).kind);
    }
    @Test public void importReplacesAtomicallyAndRevokesOldDelivery() {
        BufferSession b=new BufferSession();b.beginTarget(true);b.setEnabled(true);b.appendCommittedBlock("old");
        BufferSession.Delivery old=b.prepare(true);
        assertFalse(b.replaceImported("invalid\uD800"));assertEquals("old",b.text());
        assertTrue(b.replaceImported("new\n👋"));assertEquals("new\n👋",b.text());assertFalse(b.acknowledge(old));
        b.beginTarget(false);assertFalse(b.replaceImported("protected"));
    }
}
