-module(gtmproxy_srv).
% Created gtmproxy_srv.erl the 02:17:02 (16/06/2014) on core
% Last Modification of gtmproxy_srv.erl at 07:51:35 (03/02/2015) on core
%
% Author: "rolph" <rolphin@free.fr>

% Connects to a CNode (gtmproxy.c)
% TODO: And monitor the CNode
% CNode configuration is read from a config file located in config/
% i.e. config/gtmproxy.args
% The executable must be named 'gtmproxy' and be located in 'priv'

-export([
    start/0,
    start_link/4,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3,
    terminate/2
]).

-behaviour(gen_server).

-record(state, {
    queue,
    prefix,
    port=10000,
    childs
}).

start() ->
    gen_server:start(?MODULE, []).

start_link(Childs, Prefix, Queue, Port) ->
    gen_server:start_link(?MODULE, [Childs, Prefix, Queue, Port], []).

% callbacks
init([Childs, Prefix, Queue, Port]) ->
    {ok, #state{
        queue=Queue,
        port=Port,
        prefix=Prefix,
        childs=Childs
    }, 0};

init(_) ->
    {stop, badarg}.
    
handle_cast(_, State) ->
    {noreply, State}.

handle_call(_, _From, State) ->
    {reply, ok, State}.

handle_info(timeout, #state{
        queue=Q, 
        childs=Childs, 
        prefix=Prefix, 
        port=Port} = State) ->

    workers(Childs, Prefix, Port, Q),
    {noreply, State};

handle_info(_, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% internals
workers(Max, Prefix, Port, Queue) ->
    workers(1, Max + 1, Prefix, Port, Queue).

workers(Max, Max, _, _, _) ->
    ok;
workers( Instance, Max, Prefix, Port, Queue) ->
    PortNum = Port+Instance,
    gtmworker_srv:bind( gtmworker_sup, Instance, Prefix, PortNum, Queue ),
    workers(Instance+1, Max, Prefix, Port, Queue).

