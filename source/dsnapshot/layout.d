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

version (unittest) {
    import unit_threaded.assertions;
}

struct Snapshot {
    /// The time the snapshot was taken.
    SysTime time;
    /// Name of the snapshot. This is used to locate it.
    string name;
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
    if (diff < Duration.zero)
        return diff * -1;
    return diff;
}

/// Returns: the index of the candidate that best fit the time.
size_t bestFit(const SysTime time, const SysTime[] candidates) {
    import std.typecons : tuple;

    size_t rval = 0;
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
    bestFit(bucket, candidates).should == 4;
}

/**
 * At construction it is configured with how the snapshots should be organized
 * into buckets. How many and the space in time between them.
 *
 * It is then updated with the current layout on the storage medium.
 *
 * The only data that it relies on is the basename of the paths that are pushed
 * to it.
 */
struct Layout {
    Bucket[] buckets;
    /// The time of the bucket which a snapshot should try to match.
    const(SysTime)[] time;

    /// Snapshots that has been discarded because they do not have the best fit for any bucket.
    Snapshot[] discarded;

    this(const SysTime start, const LayoutConfig conf) {
        auto app = appender!(SysTime[])();

        SysTime curr = start;
        foreach (a; conf.spans.map!(a => repeat(a.space, a.nr)).joiner) {
            curr += a;
            app.put(curr);
        }
        time = app.data;
        buckets.length = time.length;
    }

    void put(const Snapshot s) {
        import sumtype;

        if (buckets.length == 0) {
            discarded ~= s;
            return;
        }

        const fitIdx = bestFit(s.time, time);
        const bucketTime = time[fitIdx];
        buckets[fitIdx].value = buckets[fitIdx].value.match!((Empty a) => s, (Snapshot a) {
            // Replace the snapshot in the bucket if the new one `s` is a better fit.
            if (fitness(bucketTime, s.time) < fitness(bucketTime, a.time)) {
                discarded ~= a;
                return s;
            }
            discarded ~= s;
            return a;
        });
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
        layout.put(Snapshot(base + a.dur!"hours", a.to!string));
    }

    logger.info(base);
    logger.infof("%(%s\n%)", layout.time.enumerate);
    logger.infof("%(%s\n%)", layout.buckets.enumerate);

    layout.buckets.length.should == 15;
    layout.discarded.length.shouldEqual(addSnapshotsNr - 15);

    (layout.time[0] - base).total!"hours".shouldEqual(4);
    (layout.time[4] - base).total!"hours".shouldEqual(4 * 5);
    (layout.time[5] - base).total!"hours".shouldEqual(4 * 5 + 24);
    (layout.time[9] - base).total!"hours".shouldEqual(4 * 5 + 24 * 5);
    (layout.time[10] - base).total!"hours".shouldEqual(4 * 5 + 24 * 5 + 24 * 7);
    (layout.time[14] - base).total!"hours".shouldEqual(4 * 5 + 24 * 5 + 24 * 7 * 5);
}
