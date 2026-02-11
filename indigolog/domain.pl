% ==============================================================================
% DOMAIN.PL - Cyber-Defense Domain 
% ==============================================================================

:- multifile prim_action/1, prim_fluent/1, causes_val/4, poss/2, initially/2.
:- multifile proc/2, exog_action/1, senses/2, node/1, subnet/1, depends_on/2, subv/4.

% ==============================================================================
% subv/4 - Required by IndiGolog for variable substitution (pi operator)
% ==============================================================================
subv(X, Val, X, Val) :- !.
subv(_, _, T, T) :- atomic(T), !.
subv(X, Val, [H|T], [HNew|TNew]) :- !,
    subv(X, Val, H, HNew), subv(X, Val, T, TNew).
subv(X, Val, Term, NewTerm) :-
    Term =.. [F|Args], subv_list(X, Val, Args, NewArgs), NewTerm =.. [F|NewArgs].
subv_list(_, _, [], []).
subv_list(X, Val, [H|T], [HNew|TNew]) :-
    subv(X, Val, H, HNew), subv_list(X, Val, T, TNew).

% ==============================================================================
% TOPOLOGY ( Star topology with DB hub)
% ==============================================================================
node(web_server_1).
node(web_server_2).
node(db_server).
node(workstation_a).

subnet(subnet_alpha).
subnet(subnet_beta).

depends_on(web_server_1, db_server).
depends_on(web_server_2, db_server).

% ==============================================================================
% PRIMITIVE ACTIONS
% ==============================================================================
prim_action(scan(N))            :- node(N).
prim_action(isolate_node(N))    :- node(N).
prim_action(patch(N))           :- node(N).
prim_action(reconnect(N))       :- node(N).
prim_action(restore_backup(N))  :- node(N).
prim_action(restart_router(S))  :- subnet(S).
prim_action(verify_connection(S)) :- subnet(S).
prim_action(wait_step).

% Sensing: scan senses infection status
senses(scan(N), infected(N)) :- node(N).

% Exogenous actions (triggered externally via GUI)
exog_action(alert_intrusion(N)) :- node(N).
exog_action(service_crash(S))   :- subnet(S).
exog_action(network_reset).

% ==============================================================================
% FLUENTS
% ==============================================================================
prim_fluent(isolated(N))        :- node(N).
prim_fluent(infected(N))        :- node(N).
prim_fluent(clean(N))           :- node(N).
prim_fluent(subnet_online(S))   :- subnet(S).
prim_fluent(service_degraded(N)) :- node(N).

% ==============================================================================
% INITIAL STATE - All nodes clean, connected, subnets online
% ==============================================================================
initially(clean(N), true)            :- node(N).
initially(isolated(N), false)        :- node(N).
initially(infected(N), false)        :- node(N).
initially(subnet_online(S), true)    :- subnet(S).
initially(service_degraded(N), false) :- node(N).

% ==============================================================================
% PRECONDITIONS (poss)
% ==============================================================================
% restore_backup: must be isolated AND clean (PDF Legality Task)
poss(restore_backup(N), and(isolated(N), clean(N)))  :- node(N).
% restart_router: subnet must be down
poss(restart_router(S), neg(subnet_online(S)))        :- subnet(S).
poss(verify_connection(_), true).
% isolate: node must NOT already be isolated
poss(isolate_node(N), neg(isolated(N)))               :- node(N).
% patch: node must be infected AND isolated
poss(patch(N), and(infected(N), isolated(N)))         :- node(N).
% reconnect: must be isolated AND clean
poss(reconnect(N), and(isolated(N), clean(N)))        :- node(N).
poss(scan(_), true).
poss(wait_step, true).
% Exogenous actions are always possible
poss(alert_intrusion(_), true).
poss(service_crash(_), true).
poss(network_reset, true).

% ==============================================================================
% CAUSAL LAWS (causes_val/4)
% ==============================================================================
causes_val(restart_router(S), subnet_online(S), true, true) :- subnet(S).
causes_val(isolate_node(N), isolated(N), true, true) :- node(N).

% ADL conditional effect: isolating DB degrades dependent web servers
causes_val(isolate_node(DB), service_degraded(WS), true, depends_on(WS, DB)).

causes_val(patch(N), clean(N), true, true)       :- node(N).
causes_val(patch(N), infected(N), false, true)   :- node(N).
causes_val(reconnect(N), isolated(N), false, true) :- node(N).
causes_val(reconnect(DB), service_degraded(WS), false, depends_on(WS, DB)).
causes_val(restore_backup(N), clean(N), true, true) :- node(N).

% Exogenous effects
causes_val(alert_intrusion(N), infected(N), true, true)  :- node(N).
causes_val(alert_intrusion(N), clean(N), false, true)    :- node(N).
causes_val(service_crash(S), subnet_online(S), false, true) :- subnet(S).
causes_val(network_reset, subnet_online(S), true, true)  :- subnet(S).

% ==============================================================================
% DERIVED FLUENT (PDF Projection Task)
% ==============================================================================
service_available(Node, History) :-
    node(Node),
    holds(neg(isolated(Node)), History),
    holds(neg(service_degraded(Node)), History).
