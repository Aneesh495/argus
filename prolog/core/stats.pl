/*
 * Module: argus_stats
 * Purpose: Statistical analytics, streaming percentiles, and anomaly detection algorithms.
 * Implements exact percentile interpolation, Welford's online variance, and Z-score testing.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_stats, [
    percentile/3,
    percentile_summary/5,
    welford_stats/4,
    ewma/4,
    z_score/4,
    is_anomalous_latency/5,
    list_mean/2,
    list_median/2
]).

:- use_module(library(lists)).

/**
 * percentile(+Values, +P, -Result)
 * Computes the P-th percentile (0 <= P <= 100) using linear interpolation.
 */
percentile([], _, 0.0) :- !.
percentile([X], _, FloatVal) :- !, FloatVal is float(X).
percentile(Values, P, Result) :-
    msort(Values, Sorted),
    length(Sorted, N),
    Rank is (P / 100.0) * (N - 1),
    LowerIdx is floor(Rank),
    UpperIdx is ceil(Rank),
    Fraction is Rank - LowerIdx,
    nth0(LowerIdx, Sorted, V1),
    nth0(UpperIdx, Sorted, V2),
    Result is V1 + Fraction * (V2 - V1).

/**
 * percentile_summary(+Values, -P50, -P90, -P95, -P99)
 */
percentile_summary(Values, P50, P90, P95, P99) :-
    percentile(Values, 50, P50),
    percentile(Values, 90, P90),
    percentile(Values, 95, P95),
    percentile(Values, 99, P99).

/**
 * list_mean(+Values, -Mean)
 */
list_mean([], 0.0) :- !.
list_mean(Values, Mean) :-
    sum_list(Values, Sum),
    length(Values, N),
    Mean is Sum / N.

/**
 * list_median(+Values, -Median)
 */
list_median(Values, Median) :-
    percentile(Values, 50, Median).

/**
 * welford_stats(+Values, -Mean, -Variance, -StdDev)
 * Computes mean, sample variance, and sample standard deviation using Welford's algorithm.
 */
welford_stats([], 0.0, 0.0, 0.0) :- !.
welford_stats([X], FloatX, 0.0, 0.0) :- !, FloatX is float(X).
welford_stats([H|T], Mean, Variance, StdDev) :-
    welford_loop(T, 1, float(H), 0.0, Mean, M2),
    length([H|T], N),
    Variance is M2 / (N - 1),
    StdDev is sqrt(max(0.0, Variance)).

welford_loop([], _, Mean, M2, Mean, M2).
welford_loop([X|Rest], Count, MeanIn, M2In, MeanOut, M2Out) :-
    NewCount is Count + 1,
    Delta is X - MeanIn,
    NewMean is MeanIn + Delta / NewCount,
    Delta2 is X - NewMean,
    NewM2 is M2In + Delta * Delta2,
    welford_loop(Rest, NewCount, NewMean, NewM2, MeanOut, M2Out).

/**
 * ewma(+OldEwma, +NewValue, +Alpha, -UpdatedEwma)
 * Computes exponential weighted moving average: Updated = Alpha * New + (1 - Alpha) * Old.
 */
ewma(Old, New, Alpha, Updated) :-
    Updated is Alpha * New + (1.0 - Alpha) * Old.

/**
 * z_score(+Value, +Mean, +StdDev, -Z)
 * Computes Z-score standard score: (Value - Mean) / StdDev.
 */
z_score(Value, Mean, StdDev, Z) :-
    StdDev > 0.00001, !,
    Z is (Value - Mean) / StdDev.
z_score(Value, Mean, _, 0.0) :-
    Value =:= Mean, !.
z_score(Value, Mean, _, 999.0) :-
    Value > Mean, !.
z_score(_, _, _, -999.0).

/**
 * is_anomalous_latency(+Duration, +BaselineMean, +BaselineStdDev, +ThresholdZ, -IsAnomaly)
 * True if latency deviates beyond ThresholdZ standard deviations from baseline.
 */
is_anomalous_latency(Duration, Mean, StdDev, ThresholdZ, true) :-
    z_score(Duration, Mean, StdDev, Z),
    Z >= ThresholdZ, !.
is_anomalous_latency(_, _, _, _, false).
