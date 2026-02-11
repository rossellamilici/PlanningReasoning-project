% ==============================================================================
% REASONING_TESTS.PL 
% ==============================================================================

:- ensure_loaded('indigolog_plain.pl').
:- ensure_loaded('domain.pl').
:- ensure_loaded('agent_logic.pl').

% Helper: extract action list from IndiGolog path trace
extract_actions([], []).
extract_actions([_, H1, _, H2 | Rest], [Action | Actions]) :-
    H2 = [Action | H1], !,
    extract_actions([_, H2 | Rest], Actions).
extract_actions([_, _ | Rest], Actions) :-   % FIX: was Actions]) - extra bracket
    extract_actions(Rest, Actions).

% ==============================================================================
% TASK 1: LEGALITY 
% ==============================================================================
% Scenario: Attempting restore_backup(Node) on infected/connected node
% Expected: Illegal (precondition requires isolated AND clean)

test_legality :-
    nl, writeln('=== TASK 1: LEGALITY ==='),
    writeln('Testing preconditions of restore_backup'), nl,

    % 1a. restore_backup without isolation → should be blocked
    write('1a. restore_backup(db_server) without isolation... '),
    (   \+ holds(isolated(db_server), [])
    ->  writeln('BLOCKED (correct: not isolated)')
    ;   writeln('FAIL')
    ),

    % 1b. restore_backup on infected node → should be blocked
    write('1b. restore_backup(db_server) when infected... '),
    H1 = [alert_intrusion(db_server)],
    (   \+ holds(clean(db_server), H1)
    ->  writeln('BLOCKED (correct: not clean)')
    ;   writeln('FAIL')
    ),

    % 1c. restore_backup when isolated AND clean → should be allowed
    write('1c. restore_backup(db_server) when isolated+clean... '),
    H2 = [isolate_node(db_server), patch(db_server)],
    (   holds(and(isolated(db_server), clean(db_server)), H2)
    ->  writeln('ALLOWED (correct)')
    ;   writeln('FAIL')
    ),
    nl.

% ==============================================================================
% TASK 2: PROJECTION 
% ==============================================================================
% Scenario: [isolate_node(db_server)]
% Query: service_available(web_server_1)?
% Expected: False (isolating DB degrades dependent web servers)

test_projection :-
    nl, writeln('=== TASK 2: PROJECTION ==='),
    writeln('After isolate_node(db_server):'),
    writeln('  Query: service_available(web_server_1)?'), nl,

    ActionList = [isolate_node(db_server)],

    write('  service_degraded(web_server_1)? '),
    (   holds(service_degraded(web_server_1), ActionList)
    ->  writeln('TRUE (correct: ADL conditional effect)')
    ;   writeln('FALSE (wrong!)')
    ),

    write('  isolated(db_server)?            '),
    (   holds(isolated(db_server), ActionList)
    ->  writeln('TRUE')
    ;   writeln('FALSE')
    ),

    write('  service_available(web_server_1)? '),
    (   \+ service_available(web_server_1, ActionList)
    ->  writeln('FALSE (correct: dependency breaks service)')
    ;   writeln('TRUE (wrong!)')
    ),
    nl.

% ==============================================================================
% TASK 3: PLANNING 
% ==============================================================================
% Scenario: subnet_alpha is offline (after service_crash)
% Goal: Find plan to restore it using search/findpath
% Expected: [restart_router(subnet_alpha), verify_connection(subnet_alpha)]

test_planning :-
    nl, writeln('=== TASK 3: PLANNING ==='),
    writeln('Scenario: subnet_alpha is offline'),
    writeln('Goal: Find recovery plan'), nl,

    InitialHistory = [service_crash(subnet_alpha)],

    write('  Searching for plan... '),
    (   findpath(recover_subnet_procedure(subnet_alpha), InitialHistory, Path)
    ->  (   extract_actions(Path, Actions),
            writeln('FOUND'),
            format('  Plan: ~w~n', [Actions])
        )
    ;   writeln('NOT FOUND')
    ),
    nl.

% ==============================================================================
% RUN ALL TESTS
% ==============================================================================
run_all_tests :-
    nl,
    writeln('***********************************************'),
    writeln('*  REASONING TASKS VERIFICATION *'),
    writeln('***********************************************'),
    test_legality,
    test_projection,
    test_planning,
    writeln('***********************************************'), nl.

test :- run_all_tests.
