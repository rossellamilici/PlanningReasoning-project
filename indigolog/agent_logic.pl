% ==============================================================================
% AGENT_LOGIC.PL - Controllers 
% ==============================================================================
% Two controllers:
%   1. PASSIVE  - Deterministic: full scan cycle, then react
%   2. REACTIVE - Uses prioritized_interrupts to respond immediately
%                 to exogenous actions 
% ==============================================================================

:- multifile proc/2.

% ==============================================================================
% UTILITY PROCEDURES
% ==============================================================================
proc(pick(V, Cond, Prog), pi(V, if(Cond, Prog, ?(false)))).
proc(no_op, []).

% ==============================================================================
% RECOVERY PROCEDURES 
% ==============================================================================

% 
proc(recover_node_procedure(N),
    [
        isolate_node(N),
        patch(N),
        restore_backup(N),
        reconnect(N)
    ]
).

% 
proc(recover_subnet_procedure(S),
    [
        restart_router(S),
        verify_connection(S)
    ]
).

%  scans all nodes
proc(monitor_network,
    [
        scan(db_server),
        wait_step,
        scan(web_server_1),
        wait_step,
        scan(web_server_2),
        wait_step
    ]
).

% ==============================================================================
% CONTROLLER 1: PASSIVE (Deterministic, Non-Reactive)
% ==============================================================================
% Pattern: SCAN ALL → CHECK ALL → REACT → REPEAT
%
% This controller completes the FULL monitoring cycle before checking
% and reacting. It does NOT respond to exogenous events mid-cycle.
%
% Timeline example:
%   t=0: scan db_server
%   t=1: scan web_server_1
%   t=2: scan web_server_2
%   t=3: check if any infected → react
%   t=4: check if any subnet down → react
%   t=5: loop back to t=0
%
% If db_server infected at t=0.5, reaction starts at t=3 (delayed).

proc(control(passive),
    while(true,
        [
            % Phase 1: Complete monitoring cycle
            monitor_network,

            % Phase 2: React to infected nodes (explicit per-node check)
            if(infected(db_server),
                recover_node_procedure(db_server), no_op),
            if(infected(web_server_1),
                recover_node_procedure(web_server_1), no_op),
            if(infected(web_server_2),
                recover_node_procedure(web_server_2), no_op),
            if(infected(workstation_a),
                recover_node_procedure(workstation_a), no_op),

            % Phase 3: React to downed subnets
            recover_all_subnets
        ]
    )
).

% ==============================================================================
% CONTROLLER 2: REACTIVE (Responds to exogenous actions immediately)
% ==============================================================================


% Uses prioritized_interrupts: at each step, the HIGHEST priority
% interrupt whose condition holds is executed. After execution,
% ALL interrupts are re-evaluated from the top.

% Priority order:
%   1. (HIGHEST) Any node infected → recover immediately
%   2. Any subnet down → recover subnet
%   3. (LOWEST)  No threats → wait for exogenous action

% The key: when an exogenous action (alert_intrusion/service_crash)
% arrives, IndiGolog incorporates it into the history, which changes
% the truth values of fluents, triggering the appropriate interrupt.

proc(control(reactive), [prioritized_interrupts(
    [
        % Priority 1: Immediate containment of any infected node
        interrupt(n, infected(n), recover_node_procedure(n)),

        % Priority 2: Recover downed subnets (explicit per-subnet)
        interrupt(neg(subnet_online(subnet_alpha)),
            recover_subnet_procedure(subnet_alpha)),
        interrupt(neg(subnet_online(subnet_beta)),
            recover_subnet_procedure(subnet_beta)),

        % Priority 3 (lowest): Idle - wait for exogenous events
        interrupt(true, ?(wait_exog_action))
    ]
)]).

% ==============================================================================
% CONTROLLER 3: REACTIVE-POLL 
% ==============================================================================
% We used a while loop with explicit checks after each scan.
% It scans ALL nodes (not just db_server) and reacts after each scan.

% Recover subnets - explicit check for each (avoids some/pick binding issues)
proc(recover_all_subnets,
    [
        if(neg(subnet_online(subnet_alpha)),
            recover_subnet_procedure(subnet_alpha),
            no_op
        ),
        if(neg(subnet_online(subnet_beta)),
            recover_subnet_procedure(subnet_beta),
            no_op
        )
    ]
).

%  check and recover any infected node 
proc(recover_any_infected,
    [
        if(infected(db_server),
            recover_node_procedure(db_server), no_op),
        if(infected(web_server_1),
            recover_node_procedure(web_server_1), no_op),
        if(infected(web_server_2),
            recover_node_procedure(web_server_2), no_op),
        if(infected(workstation_a),
            recover_node_procedure(workstation_a), no_op)
    ]
).

proc(control(reactive_poll),
    while(true,
        [
            scan(db_server),
            recover_any_infected,
            recover_all_subnets,
            wait_step,

            scan(web_server_1),
            recover_any_infected,
            recover_all_subnets,
            wait_step,

            scan(web_server_2),
            recover_any_infected,
            recover_all_subnets,
            wait_step
        ]
    )
).
