/*
 * Unit tests for Argus diagnostic engine modules:
 * Abductive Meta-Interpreter, Hypotheses, Explanations, Causal SCM, and Counterfactuals.
 *
 * All rights reserved. Apache-2.0 License.
 */

:- module(test_engine, [
    run_engine_tests/0
]).

:- use_module(library(plunit)).
:- use_module('../../prolog/engine/abductive').
:- use_module('../../prolog/engine/hypothesis').
:- use_module('../../prolog/engine/explanation').
:- use_module('../../prolog/engine/causal').
:- use_module('../../prolog/engine/counterfactual').

run_engine_tests :-
    run_tests([abductive, hypothesis, explanation, causal, counterfactual]).

% Dynamic background theory for abductive testing
:- dynamic user:symptom/2.
:- dynamic user:failure_cause/2.

% Test background rules:
user:symptom(http_504, gateway) :- user:failure_cause(timeout, auth).
user:symptom(http_504, gateway) :- user:failure_cause(network_partition, auth).

:- begin_tests(abductive).

test(abductive_proof_and_minimal_cost) :-
    clear_abductive_kb,
    % Register abducibles with costs (timeout is cheaper/more common than network partition)
    register_abducible(failure_cause/2, 10),
    % Integrity constraint: cannot be both timeout and network_partition simultaneously
    register_ic(ic((hyp(failure_cause(timeout, auth)), hyp(failure_cause(network_partition, auth))))),
    
    abduce_all(user:symptom(http_504, gateway), [], Solutions),
    length(Solutions, 2),
    
    abduce_minimal(user:symptom(http_504, gateway), [], BestExplanation, MinCost),
    MinCost =:= 10,
    member(hypothesis(failure_cause(_, auth), 10), BestExplanation),
    !.

:- end_tests(abductive).

:- begin_tests(hypothesis).

test(hypothesis_evidence_and_bayesian_ranking) :-
    candidate_hypothesis(connection_pool_starvation, 'database', 0.2, [], H0),
    evidence_add(H0, 'pool_active_connections == max', 3.0, H1),
    evidence_add(H1, 'connection_wait_time_ms > 5000', 4.0, H2),
    hypothesis_posterior(H2, Score, Conf),
    % Prior=0.2 * 3.0 * 4.0 = 2.4. Conf = 2.4 / (2.4 + 0.1) = 0.96
    abs(Score - 2.4) < 0.001,
    Conf > 0.95,
    
    candidate_hypothesis(network_jitter, 'database', 0.1, [ev('minor_ping_delay', 1.2)], H_Low),
    rank_hypotheses([H_Low, H2], Ranked),
    Ranked = [ranked(1, _, H2), ranked(2, _, H_Low)].

:- end_tests(hypothesis).

:- begin_tests(explanation).

test(explanation_report_and_json_serialization) :-
    explanation_create(pool_exhaustion, 'order-db', 0.94, ['order-db', 'order-svc', 'api-gw'],
                       [ev('pool_usage=100%', 2.5)], Expl),
    explanation_to_text(Expl, Text),
    sub_atom(Text, _, _, _, 'ARGUS ROOT CAUSE DIAGNOSIS'),
    sub_atom(Text, _, _, _, 'order-db -> order-svc -> api-gw'),
    explanation_to_json(Expl, JsonStr),
    string(JsonStr),
    !.

:- end_tests(explanation).

:- begin_tests(causal).

test(scm_intervention_and_causal_effect) :-
    % SCM with 3 variables: X (timeout_ms), Y (queue_depth), Z (latency_ms)
    % Y = 2 * X + 10
    % Z = Y + 50
    Vars = [x, y, z],
    Equations = [
        eq(y, add(mult(const(2), var(x)), const(10))),
        eq(z, add(var(y), const(50)))
    ],
    scm_create(Vars, Equations, [], SCM),
    
    % Intervene do(X = 100): Y = 210, Z = 260
    scm_intervene(SCM, [do(x, 100)], SCM100),
    scm_evaluate(SCM100, [], State100),
    scm_variable_get(State100, z, Z100),
    Z100 =:= 260,
    
    % Intervene do(X = 50): Y = 110, Z = 160
    scm_causal_effect(SCM, do(x, 100), do(x, 50), z, Effect),
    % Effect on Z is 260 - 160 = 100
    Effect =:= 100.

:- end_tests(causal).

:- begin_tests(counterfactual).

test(counterfactual_what_if_query) :-
    % Equations: Latency = 10 * QueueDepth + U_noise
    Vars = [queue_depth, latency],
    Equations = [
        eq(latency, add(mult(const(10), var(queue_depth)), var(u_noise)))
    ],
    scm_create(Vars, Equations, [u_noise], SCM),
    
    % In the actual incident, QueueDepth was 50, Latency was 800 ms.
    % Under the model, DetVal = 10 * 50 = 500, so U_noise = 800 - 500 = 300 ms!
    Observed = [queue_depth=50, latency=800],
    
    % Counterfactual question: What would latency have been if QueueDepth had been clamped to 10?
    % Expected counterfactual latency: 10 * 10 + 300 (abduced noise) = 400 ms!
    counterfactual_query(SCM, Observed, do(queue_depth, 10), latency, CfLatency),
    CfLatency =:= 400.

:- end_tests(counterfactual).
