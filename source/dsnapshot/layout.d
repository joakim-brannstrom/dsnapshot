/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

# Algorithm
1. Construct the layout consisting of a number of consecutive slots with a
   duration between them.
2. Fill the slots with snapshots that exists using a "best fit" algorithm.
3. Rotate the snapshots.

# Rotate algorithm
Most of the time the rotation is automatic because the layout is moving in
time forward and sooner or later a bucket has nothing in it.  The purpose of
this rotation is to ensure that snapshots are kept even over longer
distances in time such that if there is an empty space then it is used.
This most probably happens when the differences is large between two spans
such if a span was 1 hour followed by another that is 1 month. It could very
well happen that multiple month buckets end up empty.

1. Start from the back.
2. If a position is empty then take its left neighboar.

# Best fit
The best fitting snapshot is the one with the lowest difference between the
buckets time and the snapshots actual time.
*/
module dsnapshot.layout;

import logger = std.experimental.logger;
import std.algorithm : joiner, map;
import std.array : appender;
import std.datetime : SysTime, Duration, dur, Clock;
import std.range : repeat, enumerate;
import std.typecons : Nullable;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

/// Name of an existing snapshot.
struct Name {
    string value;
}

struct Snapshot {
    /// The time the snapshot was taken.
    SysTime time;
    /// Name of the snapshot. This is used to locate it.
    Name name;
}

/// Represent an empty position in the snapshot layout.
struct Empty {
}

struct Bucket {
    import sumtype;

    SumType!(Empty, Snapshot) value;
}

/// It is always positive. The closer to zero the better fit.
Duration fitness(const SysTime a, const SysTime b) {
    auto diff = b - a;
    if (diff.isNegative)
        return diff * -1;
    return diff;
}

/// Returns: the index of the candidate that best fit the time.
Nullable!size_t bestFit(const SysTime time, const SysTime[] candidates) {
    import std.typecons : tuple;

    typeof(return) rval;
    auto curr = Duration.max;
    foreach (a; candidates.enumerate.map!(a => tuple(a.index, fitness(time, a.value)))) {
        if (a[1] < curr) {
            rval = a[0];
            curr = a[1];
        }
    }

    return rval;
}

@("shall find the candidate that has the best fitness for the specific time")
unittest {
    import std.array : array;
    import std.range : iota;

    auto candidates = iota(0, 10).map!(a => Clock.currTime + a.dur!"hours").array;

    const bucket = Clock.currTime + 4.dur!"hours";
    bestFit(bucket, candidates).get.should == 4;
}

/**
 * At construction it is configured with how the snapshots should be organized
 * into buckets. How many and the space in time between them.
 *
 * It is then updated with the current layout on the storage medium.
 *
 * The only data that it relies on is the basename of the paths that are pushed
 * to it.
 *
 * It operates on two passes.
 * During the first pass snapshots are added to the buckets following a best
 * fit algorithm.  Snapshots are never discarded at this stage. If a snapshot
 * do not fit in a bucket or is replaced it is moved to a waiting list.
 *
 * During the second pass the waiting snapshots are mapped back to the buckets
 * via the same best fit algorithm.  The difference here is that the buckets
 * "time" is matched against all waiting snapshots. This is the reverse of the
 * first pass.
 * */
struct Layout {
    import sumtype;

    Bucket[] buckets;
    /// The time of the bucket which a snapshot should try to match.
    const(SysTime)[] time;

    /// Snapshots collected for pass two.
    Snapshot[] waiting;

    /// Snapshots that has been discarded because they do not have the best fit for any bucket.
    Snapshot[] discarded;

    this(const SysTime start, const LayoutConfig conf) {
        // configure the buckets
        auto app = appender!(SysTime[])();
        SysTime curr = start;
        foreach (a; conf.spans.map!(a => repeat(a.space, a.nr)).joiner) {
            curr -= a;
            app.put(curr);
        }
        time = app.data;
        buckets.length = time.length;
    }

    Nullable!(Snapshot) firstFullBucket() const {
        typeof(return) rval;
        foreach (a; buckets) {
            bool done;
            a.value.match!((Empty a) {}, (Snapshot a) { done = true; rval = a; });
            if (done)
                break;
        }
        return rval;
    }

    bool empty() const {
        return buckets.length == 0;
    }

    /// Returns: the time of the snapshot that is in the bucket
    Nullable!SysTime snapshotTimeInBucket(size_t idx) {
        typeof(return) rval;
        if (idx >= buckets.length)
            return rval;

        buckets[idx].value.match!((Empty a) {}, (Snapshot a) { rval = a.time; });
        return rval;
    }

    void put(const Snapshot s) {
        if (buckets.length == 0) {
            discarded ~= s;
            return;
        }

        const fitIdx = bestFit(s.time, time);
        if (fitIdx.isNull) {
            waiting ~= s;
            return;
        }

        const bucketTime = time[fitIdx];
        buckets[fitIdx].value = buckets[fitIdx].value.match!((Empty a) => s, (Snapshot a) {
            // Replace the snapshot in the bucket if the new one `s` is a better fit.
            if (fitness(bucketTime, s.time) < fitness(bucketTime, a.time)) {
                waiting ~= a;
                return s;
            }
            waiting ~= s;
            return a;
        });
    }

    /// Pass two. Moving waiting to either buckets or discarded.
    void finalize() {
        import std.algorithm : remove;
        import std.array : array;

        if (buckets.length == 0 || waiting.length == 0) {
            return;
        }

        scope (exit)
            waiting = null;

        auto waitingTimes = waiting.map!(a => a.time).array;
        size_t bucketIdx;

        while (bucketIdx < buckets.length) {
            scope (exit)
                bucketIdx++;

            const fitIdx = bestFit(time[bucketIdx], waitingTimes);
            if (fitIdx.isNull) {
                continue;
            }

            buckets[bucketIdx].value = buckets[bucketIdx].value.match!((Empty a) {
                auto s = waiting[fitIdx];
                waiting = waiting.remove(fitIdx.get);
                waitingTimes = waitingTimes.remove(fitIdx.get);
                return s;
            }, (Snapshot a) => a);
        }

        discarded ~= waiting;
    }

    import std.range : isOutputRange;

    string toString() @safe const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;
        import std.range : enumerate, put;

        put(w, "Bucket nr: Best Fit Time - Content\n");
        foreach (a; buckets.enumerate)
            formattedWrite(w, "%s: %s - %s\n", a.index, time[a.index], a.value);

        if (waiting.length != 0)
            put(w, "waiting\n");
        foreach (a; waiting.enumerate)
            formattedWrite(w, "%s: %s\n", a.index, a.value);

        if (discarded.length != 0)
            put(w, "Discarded\n");
        foreach (a; discarded.enumerate)
            formattedWrite(w, "%s: %s\n", a.index, a.value);
    }
}

/// Configuration for a span of snapshots in a layout.
struct Span {
    uint nr;
    Duration space;
}

/// Configuration of a layout consisting of a number of span configs.
struct LayoutConfig {
    Span[] spans;
}

@(
        "shall be a layout of 15 snapshots with increasing time between them when configured with three spans")
unittest {
    import std.conv : to;
    import std.range : iota;

    const base = Clock.currTime;

    auto conf = LayoutConfig([
            Span(5, 4.dur!"hours"), Span(5, 1.dur!"days"), Span(5, 7.dur!"days")
            ]);
    auto layout = Layout(base, conf);

    immutable addSnapshotsNr = 5 * 4 + 5 * 24 + 5 * 24 * 7;

    // completely fill up the layout
    foreach (a; iota(0, addSnapshotsNr)) {
        layout.put(Snapshot(base - a.dur!"hours", a.to!string.Name));
    }

    //logger.info(base);
    //logger.info(layout);

    layout.buckets.length.should == 15;
    layout.waiting.length.shouldEqual(addSnapshotsNr - 15);

    //logger.info(layout);
    layout.finalize;
    //logger.info(layout);

    layout.waiting.length.shouldEqual(0);
    layout.discarded.length.shouldEqual(addSnapshotsNr - 15);

    (base - layout.time[0]).total!"hours".shouldEqual(4);
    (base - layout.time[4]).total!"hours".shouldEqual(4 * 5);
    (base - layout.time[5]).total!"hours".shouldEqual(4 * 5 + 24);
    (base - layout.time[9]).total!"hours".shouldEqual(4 * 5 + 24 * 5);
    (base - layout.time[10]).total!"hours".shouldEqual(4 * 5 + 24 * 5 + 24 * 7);
    (base - layout.time[14]).total!"hours".shouldEqual(4 * 5 + 24 * 5 + 24 * 7 * 5);
}
