/*
 * Module: argus_hypothesis
 * Purpose: Diagnostic hypothesis representation, evidence collation, and Bayesian scoring.
 * Manages candidate failure hypotheses and tracks causal evidence paths.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(argus_hypothesis, [
    candidate_hypothesis/5,
    evidence_add/4,
    hypothesis_posterior/3,
    rank_hypotheses/2,
    format_hypothesis/2
]).

:- use_module(library(lists)).

/**
 * candidate_hypothesis(?FaultType, ?TargetService, ?PriorProbability, ?EvidenceList, -Hypothesis)
 */
candidate_hypothesis(FaultType, TargetService, Prior, Evidence,
                     cand_hyp(FaultType, TargetService, Prior, Evidence)).

/**
 * evidence_add(+HypIn, +EvidenceItem, +Weight, -HypOut)
 * Appends supporting evidence with likelihood weight to hypothesis.
 */
evidence_add(cand_hyp(Fault, Svc, Prior, EvList), Item, Weight,
             cand_hyp(Fault, Svc, Prior, [ev(Item, Weight)|EvList])).

/**
 * hypothesis_posterior(+Hypothesis, -PosteriorScore, -NormalizedConfidence)
 * Computes posterior probability score from prior and evidence likelihood products:
 * Score = Prior * Product(LikelihoodWeights).
 */
hypothesis_posterior(cand_hyp(_, _, Prior, EvidenceList), Score, Confidence) :-
    foldl(mult_weight, EvidenceList, Prior, Score),
    Confidence is min(0.999, Score / (Score + 0.1)).

mult_weight(ev(_, Weight), Acc, Result) :-
    Result is Acc * Weight.

/**
 * rank_hypotheses(+Hypotheses, -RankedList)
 * Ranks candidate hypotheses in descending order of posterior confidence.
 */
rank_hypotheses(Hypotheses, Ranked) :-
    findall(NegConf-Hyp, (
        member(Hyp, Hypotheses),
        hypothesis_posterior(Hyp, _, Conf),
        NegConf is -Conf
    ), Scored),
    sort(1, @=<, Scored, Sorted),
    findall(ranked(Rank, Conf, Hyp), (
        nth1(Rank, Sorted, NegConf-Hyp),
        Conf is -NegConf
    ), Ranked).

/**
 * format_hypothesis(+Hypothesis, -FormattedString)
 */
format_hypothesis(cand_hyp(Fault, Svc, _, EvList), Formatted) :-
    length(EvList, EvCount),
    format(atom(Formatted), "Hypothesis(~w on ~w, evidence_count=~w)", [Fault, Svc, EvCount]).
format_hypothesis(ranked(Rank, Conf, cand_hyp(Fault, Svc, _, EvList)), Formatted) :-
    Pct is Conf * 100.0,
    length(EvList, EvCount),
    format(atom(Formatted), "#~w: ~w on ~w [Confidence: ~1f%, Evidence items: ~w]",
           [Rank, Fault, Svc, Pct, EvCount]).
