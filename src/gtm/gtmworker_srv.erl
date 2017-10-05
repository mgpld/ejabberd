-module(gtmworker_srv).
% Created gtmworker_srv.erl the 02:17:02 (16/06/2014) on core
%% Last Modification of gtmworker_srv.erl at 08:39:47 (05/10/2017) on core
%
% Author: "rolph" <rolphin@free.fr>

% Start and monitor a specific CNode
% Start and monitor the parallel erlang process too


-behaviour(gen_server).

-include("logger.hrl").

-export([ 
    start/4, 
    start_link/4,
    stop/1
]).

-export([ 
    bind/5
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-record(state, {
    instance,
    prefix,
    port,
    name,
    pid,
    ospid,
    queue,
    queries
}).


-define( DEFAULT_TIMEOUT, 30000).

% api
start(Instance, Prefix, PortNum, Queue) ->
    gen_server:start(?MODULE, [Instance, Prefix, PortNum, Queue], []).

start_link(Instance, Prefix, PortNum, Queue) ->
    gen_server:start_link(?MODULE, [Instance, Prefix, PortNum, Queue], []).

stop(Srv) ->
    gen_server:cast(Srv, stop).

bind(Supervisor, Instance, Prefix, PortNum, Queue) ->
    ChildSpec = {
        Instance,
        { ?MODULE, start_link, [ Instance, Prefix, PortNum, Queue ] },
        transient,
        5000,
        worker,
        [?MODULE]
    },
    supervisor:start_child(Supervisor, ChildSpec).
    
% behaviour
init([ Instance, Prefix, PortNum, Queue ]) ->
    process_flag(trap_exit, true),
    Node = list_to_atom(Prefix ++ integer_to_list(Instance) ++ "@localhost"),
    {ok, #state{
        instance=Instance,
        port=PortNum,
        prefix=Prefix,
        queue=Queue,
        name=Node,
        queries=0}, 0}.

handle_call(_Any, _From, State) ->
    {reply, undefined, State}.

handle_cast(stop, State) ->
    Reason = normal,
    {stop, Reason, State};

handle_cast(_Any, State) ->
    {noreply, State}.

% If the proxy erlang process fails, restart it
handle_info({'EXIT', Pid, _Reason}, #state{name=Node, queue=Queue, pid=Pid} = State) ->
    NewPid = do_spawn(Node, Queue),
    {noreply, State#state{pid=NewPid}};

% The CNode stopped as expected
handle_info({'EXIT', Pid, {exit_status, 0}}, #state{name=Node, queue=Queue, pid=Worker, ospid=Pid} = State) ->
    error_logger:info_msg(?MODULE_STRING " CNode: ~p for Node: ~p stopped", [ Pid, Node ]),
    remove_worker(Queue, Worker),
    {stop, normal, State};

% If the CNode fails, then kills the proxy erlang process and stop (supervisor will restart me)
handle_info({'EXIT', Pid, _Reason}, #state{name=Node, queue=Queue, pid=Worker, ospid=Pid} = State) ->
    error_logger:error_msg(?MODULE_STRING " CNode: ~p for Node: ~p exited: ~p", [ Pid, Node, _Reason ]),
    remove_worker(Queue, Worker),
    {stop, {error, Node}, State};

handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State};

handle_info(timeout, #state{
        instance=Instance, 
        port=PortNum, 
        prefix=Prefix,
        name=Node, 
        queue=Queue, 
        pid=undefined} = State) ->
    {true, Node} ! stop, % Stop any old instance of Node...
    case child(Prefix, PortNum, Instance) of
        {error, _} = Error ->
            {stop, Error, State};

        NewOsPid ->
            NewPid = do_spawn(Node, Queue),
            {noreply, State#state{pid=NewPid, ospid=NewOsPid}}
    end.

code_change(_, State, _Vsn) ->
    {ok, State}.

terminate( normal, #state{name=Node, queue=Queue, pid=Worker}) ->
    error_logger:info_msg(?MODULE_STRING " Stopping CNode: ~p\n", [ Node ]),
    remove_worker(Queue, Worker),
    {false, Node} ! stop;
    
terminate( shutdown, #state{name=Node, queue=Queue, pid=Worker}) ->
    error_logger:info_msg(?MODULE_STRING " Application shutdown stopping CNode: ~p\n", [ Node ]),
    remove_worker(Queue, Worker),
    {false, Node} ! stop;

terminate(_Reason, #state{name=Node}) ->
    {false, Node} ! stop.

% internals
do_spawn(Name, Queue) ->
    spawn_link( fun() -> 
        worker(Name, Queue, infinity) 
    end).

worker(_Node, _Queue, 0) ->
    ok;
worker(Node, Queue, infinity) ->
    worker(Node, Queue, infinity, 0).

worker(Node, Queue, infinity, Count) ->
    valve_srv:poll( Queue, fun
        ({call, Module, Key, Value}) ->
            q(Node, Module, Key, Value);
        ({call, X}) -> 
            q(3, X, Node)
    end), 
    worker(Node, Queue, infinity, Count+1).

remove_worker(Queue, Pid) ->
    exit(Pid, kill),
    valve_srv:remove( Queue, Pid ).

% Calling the C Node see dbs.c
q(Node, Module, Key, Value) ->
    {true, Node} ! {Module, self(), Key, Value},
    receive
        _Any ->
            _Any
    after ?DEFAULT_TIMEOUT ->
        {error, timeout}
    end.

q(Code, Args, Node) ->
    Query = make_query(Args),
    {true, Node} ! {Code, self(), Query},
    receive
        _Any ->
            _Any
    after ?DEFAULT_TIMEOUT ->
        {error, timeout}
    end.

make_query([ Function, Module, Args]) ->
    [ Function, $^, Module, $(, gtmproxy_fmt:args(Args), $) ];
    
make_query(_) ->
    {error, badarg}.

% CNode part
child(Prefix, PortNum, InstanceId) ->
    case application:get_env(ejabberd, gtmproxy) of
        {ok, Config} ->
            case file:consult(Config) of
                {ok, Env} ->
                    spawn_link( fun() ->
                        cnode( Prefix, PortNum, InstanceId, Env )
                    end);
                _ ->
                    error_logger:error_msg(?MODULE_STRING " Missing config file: ~p", [ Config ]),
                    {error, enoent}
            end;

        _ ->
            error_logger:error_msg(?MODULE_STRING " Missing path for config file...", []),
            {error, einval}
    end.
            
cnode(Prefix, PortNum, InstanceId, Env) ->
    Options = [ 
        {args, [ integer_to_list(PortNum), Prefix, integer_to_list(InstanceId) ]},
        {env, Env},
        exit_status,
        binary
    ],

    Key = "GTMDRIVER",
    {value, {Key, GtmDriver}} = lists:keysearch(Key, 1, Env),

    Port = erlang:open_port( 
        {spawn_executable, GtmDriver},
        Options),
    
    loop(Port, InstanceId).

loop(Port, InstanceId) ->
    receive 
        {Port, {exit_status, _} = Reason} ->
            error_logger:error_msg(?MODULE_STRING "~.p (~p) [GTM] Instance: ~p, Port: ~p exited with reason: ~p", [ ?LINE, self(), InstanceId, Port, Reason]),
            exit(Reason);
            
        _Data ->
            error_logger:info_msg(?MODULE_STRING ".~p (~p) [GTM] Instance (~p): ~p\n", [ ?LINE, self(), InstanceId, _Data ]),
            loop(Port, InstanceId)
    end.
