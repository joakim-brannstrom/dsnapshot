/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

# Algorithm
1. Construct the layout consisting of a number of consecutive slots with a
   duration between them.
2. Fill the slots with snapshots that exists using a "best fit" algorithm.

# Best fit
The best fitting snapshot is the one with the lowest difference between the
buckets time and the snapshots actual time.
*/
module dsnapshot.layout;

import logger = std.experimental.logger;
import std.algorithm : joiner, map, filter;
import std.array : appender, empty;
import std.datetime : SysTime, Duration, dur, Clock, Interval;
import std.range : repeat, enumerate;
import std.typecons : Nullable;

public import dsnapshot.types : Name;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

struct Snapshot {
    /// The time the snapshot was taken.
    SysTime time;
    /// Name of the snapshot. This is used to locate it.
    Name name;
}

/// Represent an empty position in the snapshot layout.
struct Empty {
}

// TODO: replace bucket with an alias to the internal sumtype.
struct Bucket {
    import sumtype;

    SumType!(Empty, Snapshot) value;

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

        formattedWrite(w, "%s", cast() value);
    }
}

/// It is always positive. The closer to zero the better fit.
Duration fitness(const SysTime a, const SysTime b) {
    auto diff = b - a;
    if (diff.isNegative)
        return diff * -1;
    return diff;
}

/// Returns: the index of the interval that enclose `time`.
Nullable!size_t bestFitInterval(const SysTime time, const Interval!SysTime[] candidates) @safe pure nothrow {
    typeof(return) rval;
    // can't use contains because we want the intervals to be inverted, open
    // beginning and closed end. this is to put times that are on the edge in
    // the "closest to now" interval.
    foreach (a; candidates.enumerate.filter!(a => (time > a.value.begin && time <= a.value.end))) {
        rval = a.index;
        break;
    }

    return rval;
}

@("shall find the interval that contains the time")
unittest {
    import std.array : array;
    import std.range : iota;

    const base = Clock.currTime;
    const offset = 5.dur!"minutes";

    auto candidates = iota(0, 10).map!(a => Interval!SysTime(base - (a + 1)
            .dur!"hours", base - a.dur!"hours")).array;

    // |---|---|---|---|---|---|
    // 0   1   2   3   4   5   6
    bestFitInterval(base - offset, candidates).get.should == 0;
    bestFitInterval(base - 4.dur!"hours" - offset, candidates).get.should == 4;
    bestFitInterval(Clock.currTime - 5.dur!"hours" - offset, candidates).get.should == 5;

    // test edge case where the times are exactly on the borders
    bestFitInterval(base, candidates).get.should == 0;
    bestFitInterval(base - 1.dur!"hours", candidates).get.should == 1;
    bestFitInterval(base - 4.dur!"hours", candidates).get.should == 4;
    bestFitInterval(base - 5.dur!"hours", candidates).get.should == 5;
}

/// Returns: the index of the candidate that best fit the time.
Nullable!size_t bestFitTime(const SysTime time, const SysTime[] candidates) {
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

    const base = Clock.currTime;
    const offset = 5.dur!"minutes";

    auto candidates = iota(0, 10).map!(a => base - a.dur!"hours").array;

    // |---|---|---|---|---|---|
    // 0   1   2   3   4   5   6
    bestFitTime(base - offset, candidates).get.should == 0;
    bestFitTime(base - 4.dur!"hours" - offset, candidates).get.should == 4;
    bestFitTime(Clock.currTime - 5.dur!"hours" - offset, candidates).get.should == 5;
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
 * The first pass is basically a histogram. It finds the bucket interval that
 * wrap the snapshot. It then checks to see if the candidate is newer than the
 * one currently in the bucket. If so it replaces it. This mean that each
 * bucket contains the latest snapshot that fit it. Snapshots are never
 * discarded at this stage. If a snapshot do not fit in a bucket or is replaced
 * it is moved to a waiting list.
 * */
struct Layout {
    import sumtype;

    Bucket[] buckets;
    /// The time of the bucket which a snapshot should try to match.
    const(Interval!SysTime)[] times;

    /// Snapshots that has been discarded because they do are not the best fit for any bucket.
    Snapshot[] discarded;

    this(const SysTime start, const LayoutConfig conf) {
        auto begin = start.toUTC;
        auto end = start.toUTC;
        auto app = appender!(Interval!SysTime[])();
        foreach (const a; conf.spans.map!(a => repeat(a.space, a.nr)).joiner) {
            try {
                end = begin;
                begin -= a;
                app.put(Interval!SysTime(begin, end));
            } catch (Exception e) {
                logger.warning(e.msg);
                logger.infof("Tried to create a bucket with time span %s -> %s from span interval %s",
                        begin, end, a);
            }
        }
        times = app.data;
        buckets.length = times.length;
    }

    Layout dup() @safe pure nothrow const {
        Layout rval;
        rval.buckets = buckets.dup;
        rval.times = times.dup;
        rval.discarded = discarded.dup;
        return rval;
    }

    bool isFirstBucketEmpty() @safe pure nothrow const @nogc {
        if (buckets.length == 0)
            return false;
        return buckets[0].value.match!((Empty a) => true, (Snapshot a) => false);
    }

    Nullable!Snapshot firstFullBucket() const {
        typeof(return) rval;
        foreach (a; buckets) {
            bool done;
            a.value.match!((Empty a) {}, (Snapshot a) { done = true; rval = a; });
            if (done)
                break;
        }

        return rval;
    }

    /// Returns: a snapshot that can be used to resume.
    Nullable!Snapshot resume() @safe pure nothrow const @nogc {
        import std.algorithm : endsWith;
        import dsnapshot.types : snapshotInProgressSuffix;

        typeof(return) rval;

        foreach (s; discarded.filter!(a => a.name.value.endsWith(snapshotInProgressSuffix))) {
            rval = s;
            break;
        }

        return rval;
    }

    bool empty() const {
        return buckets.length == 0;
    }

    /// Returns: the time of the snapshot that is in the bucket
    Nullable!SysTime snapshotTimeInBucket(size_t idx) @safe pure nothrow const @nogc {
        typeof(return) rval;
        if (idx >= buckets.length)
            return rval;

        buckets[idx].value.match!((Empty a) {}, (Snapshot a) { rval = a.time; });
        return rval;
    }

    /// Returns: the bucket which interval enclose `time`.
    Nullable!Snapshot bestFitBucket(const SysTime time) @safe const {
        typeof(return) rval;

        const fitIdx = bestFitInterval(time, times);
        if (!fitIdx.isNull) {
            buckets[fitIdx.get].value.match!((Empty a) {}, (Snapshot a) {
                rval = a;
            });
        }

        return rval;
    }

    void put(const Snapshot s) {
        if (buckets.length == 0) {
            discarded ~= s;
            return;
        }

        const fitIdx = bestFitInterval(s.time, times);
        if (fitIdx.isNull) {
            discarded ~= s;
            return;
        }

        const bucketTime = times[fitIdx];
        buckets[fitIdx].value = buckets[fitIdx].value.match!((Empty a) => s, (Snapshot a) {
            // Replace the snapshot in the bucket if the new one `s` is a better fit.
            // Using `.end` on the assumption that the latest snapshot for
            // each bucket is the most interesting. This also mean that when a
            // snapshot trickle over to a new bucket it will most probably
            // replace the old one right away because the old one is closer to
            // the `.begin` than `.end`.
            if (fitness(bucketTime.end, s.time) < fitness(bucketTime.end, a.time)) {
                discarded ~= a;
                return s;
            }
            discarded ~= s;
            return a;
        });
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
        import std.ascii : newline;

        put(w, "Bucket Nr: Interval\n");
        foreach (a; buckets.enumerate) {
            formattedWrite(w, "%9s: %s - %s\n%11s", a.index,
                    times[a.index].begin, times[a.index].end, "");
            a.value.value.match!((Empty a) { put(w, "empty"); }, (Snapshot a) {
                formattedWrite(w, "%s", a.time);
            });
            put(w, newline);
        }

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

    layout.buckets.length.should == 15;
    layout.discarded.length.shouldEqual(addSnapshotsNr - 15);

    (base - layout.times[0].begin).total!"hours".shouldEqual(4);
    (base - layout.times[4].begin).total!"hours".shouldEqual(4 * 5);
    (base - layout.times[5].begin).total!"hours".shouldEqual(4 * 5 + 24);
    (base - layout.times[9].begin).total!"hours".shouldEqual(4 * 5 + 24 * 5);
    (base - layout.times[10].begin).total!"hours".shouldEqual(4 * 5 + 24 * 5 + 24 * 7);
    (base - layout.times[14].begin).total!"hours".shouldEqual(4 * 5 + 24 * 5 + 24 * 7 * 5);
}
