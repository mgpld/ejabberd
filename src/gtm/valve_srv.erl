-module(valve_srv).

-behaviour(gen_server).

-include("logger.hrl").

-export([ 
    start/0, 
    start_link/0, start_link/1,
    stop/0, stop/1
]).

-export([
	init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3
]).

-export([
    poll/1, poll/2,
    call/2, call/3,
    cast/2,
    snap/1,
    remove/2
]).

-record(state, {
    childs,
    queue,
    miss,
    queries
}).

-define( UINT8(X), 	X:8/unsigned).
-define( UINT32(X), 	X:32/unsigned).
-define( PRODUCT,	"product").

%
start() ->
	gen_server:start(?MODULE, [], []).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

init([]) ->
    {ok, #state{    
	childs=[],
	queue=queue:new(),
	miss=0,
	queries=0} }.

stop(Srv) ->
	gen_server:cast(Srv, stop).

stop() ->
	stop(?MODULE).

snap(Srv) ->
    gen_server:call(Srv, snap).

call( Pid, Args, Timeout) ->
    gen_server:call( Pid, {Args, Timeout}, Timeout).

call( Pid, Args ) ->
    call( Pid, Args, 5000).

cast( Pid, Args ) ->
    gen_server:cast( Pid, Args).

remove( Pid, Child ) ->
    gen_server:cast( Pid, {remove, Child}).

poll( Pid ) ->
    do_poll(Pid, fun(X) -> X end, 3).

poll( Pid, Fun) ->
    do_poll( Pid, Fun, 3).

do_poll(_Pid, _, 0) ->
    ok;
do_poll(Pid, Fun, Count) ->
    case gen_server:call( Pid, poll, infinity ) of
        {ok, {Operation, {Date, Timeout}, Client} = _Args} ->
            ?DEBUG("(~p) ** will handle : ~p instance ~p.\n", [ self(), _Args, Count ]),
            case expired(Date, Timeout) of
                false -> 
                    ?DEBUG("(~p) Handle query ~p for client ~p : ~p\n", [ self(), Operation, Client, calendar:now_to_local_time(Date) ]),
                    Result = Fun( Operation ),
                    gen_server:reply( Client, Result),
                    do_poll(Pid, Fun, Count - 1);

                true ->
                    ?DEBUG("(~p) Drop query ~p for client ~p because of expire, try another\n", [ self(), Operation, Client ]),
                    do_poll(Pid, Fun, Count  - 1)
            end;

        {ok, {Operation, Client} = _Args} ->
            ?DEBUG("(~p) ** will handle : ~p instance ~p.\n", [ self(), _Args, Count ]),
            Result = Fun( Operation ),
            gen_server:reply( Client, Result),
            do_poll(Pid, Fun, Count - 1);

        _Any ->
            ?DEBUG("(~p) Err: ~p\n", [ self(), _Any ])
    end.

% Callback Calls

handle_call(snap, _From, #state{queries=Q} = State) ->
    {reply, {ok, State}, State#state{ queries=Q + 1}};

% handle_call(poll, From, #state{childs=[]} = State ) ->
%     ?DEBUG("First child: hanging\n", []),
%     {noreply, State#state{ childs=[ From ] }};

handle_call(poll, From, #state{childs=Childs, queue=Q} = State) ->
    case queue:out( Q ) of
        {{value, { _Query, _, _Client } = Args}, NewQ} ->
            ?DEBUG("Unqueue ~p/~p to ~p\n", [ _Query, _Client, From ]),
            {reply, {ok, Args}, State#state{queue=NewQ}};

        {empty, _} ->
            ?DEBUG("Nothing to do: hanging (waiting for client)\n", []),
            {noreply, State#state{ childs= [ From | Childs ] }}
    end;


handle_call({Operation, Timeout}, From, #state{childs=[], queue=Q, miss=Miss} = State) when is_tuple(Operation) ->
    ?DEBUG("No worker ready to answer query, queuing ~p/~p (~p) and hanging (waiting for worker)\n", [ Operation, From, Miss ]),
    Timer = {os:timestamp(), Timeout}, 
    Item = {Operation, Timer, From},
    NewQ = queue:in(Item, Q),
    {noreply, State#state{ queue=NewQ, miss=Miss+1 }};

handle_call({Operation, _Timeout}, From, #state{childs=[Child | Rest], queries=Queries} = State) when is_tuple(Operation) ->
    ?DEBUG("Shortcut: bypass the queue for ~p, ~p\n", [ Child, Operation ]),
    answer(Child, Operation, From),
    {noreply, State#state{childs=Rest, queries=Queries+1}};

%% Fallback method for calling gen_server:call instead of valve_srv:call
handle_call(Query, From, State) when is_tuple(Query) ->
    handle_call({ Query, 5000 }, From, State);

handle_call(_Query, _Node, State) ->
    ?DEBUG("Catchall: ~p\n", [ _Query ]),
    {reply, undefined, State}.

% Callback Casts
handle_cast({remove, Child}, #state{childs=Childs} = State) ->
    NewChilds = lists:keydelete( Child, 1, Childs ),
    {noreply, State#state{childs = NewChilds }};

handle_cast(stop, State) ->
    Reason = normal,
    {stop, Reason, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

% Info
handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State}.

% Others
terminate(_Reason, _State) ->
    ok.

code_change(_, State, _Vsn) ->
    {ok, State}.


% internals

answer(Pid, Query, Client) ->
    %?DEBUG("Sending to ~p: query to ~p for client ~p\n",  [ Pid, Query, Client ]),
    gen_server:reply( Pid, {ok, {Query, Client}}).

expired(Date, Timeout) ->
    Diff = timer:now_diff( os:timestamp(), Date ),
    ?DEBUG("Diff: ~p, Timeout: ~p\n", [ Diff, Timeout ]),
    Timeout < Diff.

