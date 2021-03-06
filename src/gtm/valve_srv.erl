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

%-define(DEBUG,true).

-ifdef(DEBUG).
-export([
    test/0,
    ask/2
]).
-endif.

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
            ?DEBUG(?MODULE_STRING "~.p ~p ** will handle : ~p instance ~p.\n", [ ?LINE, self(), _Args, Count ]),
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

        {ok, {Operation, Client} = _Args} when is_tuple(Client) ->
            ?DEBUG(?MODULE_STRING ".~p ~p ** gen_server will handle : ~p instance ~p.\n", [ ?LINE, self(), _Args, Count ]),
            Result = Fun( Operation ),
            gen_server:reply( Client, Result),
            do_poll(Pid, Fun, Count - 1);

        %{ok,[<<"canonical">>,<<"infotree">>,[1001]],<0.6744.0>,100}
        {ok, Operation, Client, TransId} when is_pid(Client) ->
            ?DEBUG(?MODULE_STRING ".~p ~p ** plain      will handle : ~p, client: ~p, transid: ~p, round ~p.\n", [ ?LINE, self(), Operation, Client, TransId, Count ]),
            Result = Fun({call, Operation}),
            Client ! {db, TransId, Result},
            do_poll(Pid, Fun, Count - 1);

        _Any ->
            ?DEBUG(?MODULE_STRING ".~p (~p) Err: ~p\n", [ ?LINE, self(), _Any ])
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
            ?DEBUG(?MODULE_STRING ".~p Unqueue ~p/~p to ~p\n", [ ?LINE, _Query, _Client, From ]),
            {reply, {ok, Args}, State#state{queue=NewQ}};

        {empty, _} ->
            ?DEBUG(?MODULE_STRING ".~p Nothing to do: hanging (waiting for client)\n", [ ?LINE ]),
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
handle_cast({Client, [ TransId | Operation ]}, #state{childs=[Child | Rest], queries=Queries} = State) ->
    ?DEBUG(?MODULE_STRING ".~p handle_cast: TransId: ~p, Operation: ~p", [ ?LINE, TransId, Operation ]),
    gen_server:reply(Child, {ok, Operation, Client, TransId}), 
    {noreply, State#state{childs=Rest, queries=Queries+1}};

handle_cast({remove, Child}, #state{childs=Childs} = State) ->
    NewChilds = lists:keydelete( Child, 1, Childs ),
    {noreply, State#state{childs = NewChilds }};

handle_cast(stop, State) ->
    Reason = normal,
    {stop, Reason, State};

handle_cast(_Msg, State) ->
    ?DEBUG(?MODULE_STRING ".~p handle_cast Default: ~p", [ ?LINE, _Msg ]),
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
    ?DEBUG("Sending to worker ~p: query: ~p for client ~p\n",  [ Pid, Query, Client ]),
    gen_server:reply( Pid, {ok, {Query, Client}}).

-ifdef(DEBUG).
ask(Pid, Args) ->
    %Now = os:timestamp(),
    {_Time, _Result} = timer:tc( ?MODULE, call, [ Pid, Args ]),
    ?DEBUG("(~p) ~p us: ~p\n", [ self(), _Time, _Result ]).

test() ->
    {ok, S} = ?MODULE:start_link(),
    ?DEBUG("~p: ~p\n", [ ?MODULE, S ]),
    spawn(?MODULE, ask, [ S, <<"Calling before any one">> ]),
    spawn(?MODULE, ask, [ S, <<"B1.">> ]),
    spawn(?MODULE, ask, [ S, <<"B2..">> ]),
    spawn(?MODULE, ask, [ S, <<"B3...">> ]),
    spawn(?MODULE, ask, [ S, <<"ahuri">> ]),
    spawn(?MODULE, ask, [ S, <<"couille">> ]),
    spawn(?MODULE, ask, [ S, <<"ahuri">> ]),
    spawn(?MODULE, ask, [ S, <<"Couillu">> ]),
    spawn(?MODULE, poll, [ S ]),
    receive after 100 -> ok end,
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    receive after 200 -> ok end,
    spawn(?MODULE, ask, [ S, <<"R1">> ]),
    spawn(?MODULE, ask, [ S, <<"ahuri debile">> ]),
    spawn(?MODULE, ask, [ S, <<"bordel bouffon">> ]),
    spawn(?MODULE, ask, [ S, <<"R3">> ]),
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    receive after 200 -> ok end,
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    receive after 200 -> ok end,
    spawn(?MODULE, poll, [ S ]),
    spawn(?MODULE, ask, [ S, <<"R4">> ]),
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    spawn(?MODULE, poll, [ S, fun keyword/1 ]),
    spawn(?MODULE, poll, [ S ]),
    spawn(?MODULE, ask, [ S, <<"R5">> ]),
    spawn(?MODULE, poll, [ S, fun valve_operations:trim/1 ]),
    spawn(?MODULE, ask, [ S, <<"R212121212121212121">> ]),
    spawn(?MODULE, poll, [ S, fun valve_operations:padd/1 ]),
    spawn(?MODULE, poll, [ S, fun valve_operations:split/1 ]),
    spawn(?MODULE, ask, [ S, <<"octopus les arrivations">> ]),
    spawn(?MODULE, poll, [ S, fun reverse/1 ]),
    receive after 2000 -> ok end,
    stop(S). 
    
keyword({call, Arg}) ->
    {true, c1@core} ! {1, self(), Arg},
    receive
	Result ->
	    Result
    after 1000 ->
	{error, timeout}
    end;
keyword(_Msg) ->
    ?DEBUG("Unhandled msg: ~p\n", [ _Msg ]).

reverse({call, Arg}) when is_binary(Arg) ->
    {ok, lists:reverse( binary_to_list( Arg ))};
reverse( Arg ) ->
    {error, {einval, Arg}}.

-endif.

expired(Date, Timeout) ->
    Diff = timer:now_diff( os:timestamp(), Date ),
    ?DEBUG("Diff: ~p, Timeout: ~p\n", [ Diff, Timeout ]),
    Timeout < Diff.

