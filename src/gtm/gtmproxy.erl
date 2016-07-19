-module(gtmproxy).
% Created gtmproxy.erl the 02:17:02 (16/06/2014) on core
% Last Modification of gtmproxy.erl at 08:53:03 (07/01/2015) on core
%
% Author: "rolph" <rolphin@free.fr>

-export([
    start/0,
    start_link/1
]).


-define(FUN_CALL, 3). % see C code gtmproxy.c

-define(DEFAULT_TIMEOUT, 60000).

start() ->
    application:start(sasl),
    application:start(gtmproxy).

start_link(Childs) ->
    Server = case valve_srv:start_link(?MODULE) of
        {ok, Pid} ->
            Pid;
        {error, {already_started, Pid}} ->
            Pid
    end,
    workers(Childs), % starts the C node and the erlang process
    {ok, Server}.

child(PortNum, InstanceId) ->
    spawn( fun() ->
    	cnode( PortNum, InstanceId )
    end).

cnode(PortNum, InstanceId) ->
    Env = [
	% {"GTMCI", "/home/bot/XMPP/C/CNode/calltab.ci"},
	% {"gtmroutines", "/home/bot/XMPP/C/CNode/gtm /opt/fis-gtm"},
	% {"gtm_dist", "/opt/fis-gtm"},
	{"gtm_noundef","YES"}, {"gtm_noceable","NO"}
	%{"gtm_repl_instname", "VM115"}, %% see gtmgbldir
	%{"gtmgbldir", "/home/bot/Databases/VM115/application.gld"}
    ],
    Options = [ 
	{args, [ integer_to_list(PortNum), integer_to_list(InstanceId) ]},
	{env, Env},
	exit_status,
	binary
    ],
    Port = erlang:open_port( 
	{spawn_executable, "priv/gtmproxy"},
	Options),
    
    loop(Port, InstanceId).

loop(Port, InstanceId) ->
    receive 
	_Data ->
	    %io:format("(~p) ~p\n", [ InstanceId, Data ]),
	    loop(Port, InstanceId)
    end.

workers(Max) ->
    {ok, Hostname} = inet:gethostname(),
    workers(1, Max, Hostname).

workers(Count, Count, _) ->
    ok;
workers(Count, Max, Hostname) ->
    child(10000+Count, Count),  
    spawn( fun() -> 
        worker(list_to_atom("c" ++ integer_to_list(Count) ++ "@" ++ Hostname), infinity) 
    end),
    workers(Count+1, Max, Hostname).

worker(_Node, 0) ->
    ok;
worker(Node, infinity) ->
    worker(Node, infinity, 0);
worker(Node, Count) ->
    valve_srv:poll( ?MODULE, fun({call, X}) -> 
	    q(?FUN_CALL, X, Node) 
    end), % m_call
    worker(Node, Count - 1). 

worker(Node, infinity, Count) ->
    valve_srv:poll( ?MODULE, fun({call, X}) -> 
	    q(?FUN_CALL, X, Node) 
    end), % m_call
    %io:format(?MODULE_STRING " ~p ", [ Count ]),
    worker(Node, infinity, Count+1).

% Calling the C Node see dbs.c
q(Code, Arg, Node) ->
    {true, Node} ! {Code, self(), Arg},
    receive
        _Any ->
            _Any
        after ?DEFAULT_TIMEOUT ->
            {error, timeout}
    end.

