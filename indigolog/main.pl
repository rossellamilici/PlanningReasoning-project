% ==============================================================================
% MAIN.PL - Entry Point for Cyber-Defense Orchestrator


:- catch(ensure_loaded('indigolog_plain.pl'), _,
    (writeln('ERROR: indigolog_plain.pl not found!'), fail)).
:- ensure_loaded('domain.pl').
:- ensure_loaded('agent_logic.pl').
:- use_module(library(socket)).
:- use_module(library(readutil)).

:- dynamic sim_infected/1, sim_isolated/1, sim_subnet_down/1.
:- dynamic gui_read_stream/1, gui_write_stream/1, gui_connected/0.

% ==============================================================================
% MAIN ENTRY POINT
% ==============================================================================
main :-
    reset_simulation,
    connect_gui,
    nl,
    writeln('=================================================='),
    writeln('   CYBER-DEFENSE ORCHESTRATOR'),
    writeln('=================================================='),
    show_menu.

show_menu :-
    nl, writeln('Controllers:'),
    writeln('  1. PASSIVE      - Full scan cycle, then react (deterministic)'),
    writeln('  2. REACTIVE     - prioritized_interrupts (needs support)'),
    writeln('  3. REACTIVE-POLL- Polling variant (always works)'),
    nl, write('Choose (1, 2, or 3): '), flush_output,
    read_line_to_string(user_input, Input),
    normalize_space(string(Choice), Input),
    (   Choice = "1" -> run_controller(passive)
    ;   Choice = "2" -> run_controller(reactive)
    ;   Choice = "3" -> run_controller(reactive_poll)
    ;   (writeln('Invalid choice.'), show_menu)
    ).

run_controller(C) :-
    format('~n>>> STARTING CONTROLLER: ~w~n', [C]),
    writeln('>>> Send events from the GUI window'),
    writeln('>>> Press Ctrl+C to stop'), nl,
    catch(
        indigolog(control(C)),
        E,
        format('~n>>> Stopped: ~w~n', [E])
    ),
    nl, writeln('>>> Controller terminated'), nl.

% ==============================================================================
% GUI CONNECTION (TCP Socket)
% ==============================================================================
% The Python GUI listens on port 9999. Prolog connects as client.
% We open TWO separate streams for read and write to avoid blocking.

connect_gui :-
    retractall(gui_read_stream(_)),
    retractall(gui_write_stream(_)),
    retractall(gui_connected),
    catch(
        (
            tcp_socket(Socket),
            tcp_connect(Socket, localhost:9999),
            tcp_open_socket(Socket, ReadStream, WriteStream),
            set_stream(ReadStream, encoding(utf8)),
            set_stream(WriteStream, encoding(utf8)),
            assertz(gui_read_stream(ReadStream)),
            assertz(gui_write_stream(WriteStream)),
            assertz(gui_connected),
            writeln('[OK] GUI connected on port 9999')
        ),
        _Error,
        writeln('[WARN] GUI not connected - running without GUI')
    ).

% Send status update to GUI: "node_name:status"
send_gui(Target, Status) :-
    gui_write_stream(Stream), !,
    catch(
        (format(Stream, '~w:~w~n', [Target, Status]), flush_output(Stream)),
        _,
        true
    ).
send_gui(_, _).  % Silently succeed if no GUI

% ==============================================================================
% SIMULATION STATE
% ==============================================================================
reset_simulation :-
    retractall(sim_infected(_)),
    retractall(sim_isolated(_)),
    retractall(sim_subnet_down(_)).

% ==============================================================================
% WORLD INTERFACE (called by IndiGolog)
% ==============================================================================
% execute/2: IndiGolog calls this to perform actions in the world.
% For sensing actions (scan), we return the sensed value.
% For regular actions, we return 'ok'.

execute(A, Result) :-
    senses(A, _), !,
    simulate_effect(A),
    get_sensing(A, Result).
execute(A, ok) :-
    simulate_effect(A).

% Sensing results from simulator state
get_sensing(scan(N), true) :- sim_infected(N), !.
get_sensing(scan(_), false).

% ==============================================================================
% wait_exog_action/0 - Block until an exogenous event arrives
% ==============================================================================
% Used by the reactive controller's idle interrupt: ?(wait_exog_action)
% Busy-waits with small sleeps, checking the socket each iteration.
% Succeeds as soon as data is available (the actual reading happens
% in exog_occurs/1, which IndiGolog calls right after).

wait_exog_action :-
    gui_connected, !,
    gui_read_stream(Stream),
    wait_for_exog(Stream).
wait_exog_action :-
    % No GUI: just sleep briefly so the loop doesn't spin at 100% CPU
    sleep(0.5).

wait_for_exog(Stream) :-
    (   catch(wait_for_input([Stream], [Stream], 0.3), _, fail)
    ->  true   % Data available! Return so IndiGolog can call exog_occurs
    ;   wait_for_exog(Stream)  % Nothing yet, keep waiting
    ).


% ==============================================================================
% EXOGENOUS ACTION INTERFACE
% ==============================================================================
% IndiGolog calls exog_occurs/1 to check for external events.
% We read from the GUI socket (non-blocking) and parse commands.

exog_occurs(Action) :-
    gui_connected,
    gui_read_stream(Stream),
    catch(
        (   read_line_from_socket(Stream, Line),
            parse_gui_command(Line, Action)
        ),
        _AnyError,
        fail   % Any socket error → no event
    ).

% Read one line from socket (non-blocking).
% Uses wait_for_input/3 with timeout 0 to check for data first.
read_line_from_socket(Stream, Line) :-
    wait_for_input([Stream], Ready, 0),     % 0 = non-blocking check
    Ready = [Stream],                        % data is available
    read_line_to_string(Stream, RawLine),
    RawLine \= end_of_file,
    % Trim whitespace (normalize_space collapses spaces and trims)
    normalize_space(string(Line), RawLine),
    Line \= "".

% Parse a line from GUI into a Prolog action term
% GUI sends lines like: "alert_intrusion(db_server)"
parse_gui_command(Line, Action) :-
    atom_string(Atom, Line),
    catch(
        term_to_atom(Term, Atom),
        _,
        fail
    ),
    Term \= end_of_file,
    process_event(Term, Action).

% ==============================================================================
% EVENT PROCESSING
% ==============================================================================
% Process incoming exogenous events from GUI.
% Update simulator state IMMEDIATELY so that sensing detects it.

process_event(alert_intrusion(N), alert_intrusion(N)) :-
    node(N),
    \+ sim_infected(N), !,
    % Update simulator state immediately
    assertz(sim_infected(N)),
    nl,
    format('[!] INTRUSION DETECTED: ~w~n', [N]),
    format('    State: ~w is now INFECTED~n', [N]),
    send_gui(N, infected).

process_event(alert_intrusion(N), alert_intrusion(N)) :-
    node(N),
    sim_infected(N), !,
    % Already infected - still return the action for IndiGolog
    format('[!] INTRUSION on ~w (already infected)~n', [N]).

process_event(service_crash(S), service_crash(S)) :-
    subnet(S),
    \+ sim_subnet_down(S), !,
    assertz(sim_subnet_down(S)),
    nl,
    format('[!] SERVICE CRASH: ~w~n', [S]),
    format('    State: ~w is now DOWN~n', [S]),
    send_gui(S, down).

process_event(service_crash(S), service_crash(S)) :-
    subnet(S),
    sim_subnet_down(S), !,
    format('[!] CRASH on ~w (already down)~n', [S]).

process_event(network_reset, network_reset) :- !,
    writeln('[!] NETWORK RESET received').

% ==============================================================================
% SIMULATOR EFFECTS
% ==============================================================================
% simulate_effect/1: Apply the side-effects of actions on simulator state.

simulate_effect(alert_intrusion(N)) :-
    format('    [exog] alert_intrusion(~w) processed~n', [N]).

simulate_effect(service_crash(S)) :-
    format('    [exog] service_crash(~w) processed~n', [S]).

simulate_effect(isolate_node(N)) :-
    assertz(sim_isolated(N)),
    send_gui(N, isolated),
    format('    [act] isolate_node(~w)~n', [N]).

simulate_effect(patch(N)) :-
    retractall(sim_infected(N)),
    send_gui(N, patching),
    format('    [act] patch(~w)~n', [N]),
    sleep(0.3).

simulate_effect(restore_backup(N)) :-
    send_gui(N, restoring),
    format('    [act] restore_backup(~w)~n', [N]),
    sleep(0.3).

simulate_effect(reconnect(N)) :-
    retractall(sim_isolated(N)),
    send_gui(N, clean),
    format('    [act] reconnect(~w)~n', [N]).

simulate_effect(restart_router(S)) :-
    retractall(sim_subnet_down(S)),
    send_gui(S, online),
    format('    [act] restart_router(~w)~n', [S]),
    sleep(0.3).

simulate_effect(verify_connection(S)) :-
    format('    [act] verify_connection(~w)~n', [S]).

simulate_effect(scan(N)) :-
    (   sim_infected(N)
    ->  format('    [scan] ~w: !! INFECTED !!~n', [N])
    ;   format('    [scan] ~w: clean~n', [N])
    ).

simulate_effect(wait_step) :-
    write('.'), flush_output, sleep(0.2).

simulate_effect(network_reset) :-
    retractall(sim_subnet_down(_)),
    writeln('    [exog] network_reset processed').

simulate_effect(_).   % Catch-all for unknown actions
