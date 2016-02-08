-module(hyp_live).
% Created hyp_live.erl the 13:33:37 (01/01/2015) on core
% Last Modification of hyp_live.erl at 20:27:25 (08/02/2016) on sd-19230
% 
% Author: "rolph" <rolphin@free.fr>

-behaviour(gen_fsm).

-include("ejabberd.hrl").
-include("logger.hrl").

-export([
    start/1,
    start_link/0, start_link/1, start_link/3, start_link/5,
    handle_event/3,
    handle_sync_event/4, handle_info/3,
    terminate/3, code_change/4, cancel/0,
    init/1,
    stop/1,
    info/1,
    next/1,
    current/1
]).

% API
-export([
    add/2,
    normal/1,
    message/2, message/3,
    users/1,
    publish/1,
    subscribe/2
]).

-export([
    route/3
]).


-define(test, true).

-ifdef(test).
-export([
    debug_link/1,
    test/0
]).
-endif.

% fsm states
-export([
    init/2, init/3,
    enroll/2, enroll/3,
    normal/2, normal/3,
    locked/2, locked/3
]).

% -define( UINT16(X),	X:16/native-unsigned).
%-define( INACTIVITY_TIMEOUT, 5 * 60000). % 5 minutes
-define( INACTIVITY_TIMEOUT, 10000). % 10 seconds

-record(question, {
    id,
    title,
    answers,
    answer
}).

-record(state,{
    roomid,
    host,
    roomref,
    creator,
    data,
    cid,
    mod, % module must implement route/4
    timeout, % timeout between questions
    question = #question{},
    users,
    inactivity_timeout
}).


debug_link( Id ) ->
    Options = [
        {debug, [{log_to_file, ?MODULE_STRING ++ ".log"}]
    }],
    gen_fsm:start_link(?MODULE, [Id], Options).

start_link( RoomId, Module, RoomRef ) ->
    gen_fsm:start_link(?MODULE, [RoomId, Module, RoomRef], []).

start_link( RoomId, Host, Creator, RoomRef, Module ) ->
    gen_fsm:start_link(?MODULE, [RoomId, Host, Creator, RoomRef, Module], []).

start_link( Id ) ->
    gen_fsm:start_link(?MODULE, [Id], []).

start( Id ) ->
    gen_fsm:start(?MODULE, [Id], []).

start_link() ->
    gen_fsm:start_link({local, ?MODULE}, ?MODULE, [], []).

cancel() ->
    gen_fsm:send_all_state_event(?MODULE, cancel).

% Add a player
add(Pid, Jid) ->
    gen_fsm:send_event(Pid, {add, Jid}).

message(Pid, Message) ->
    gen_fsm:send_event(Pid, {message, Message}).

message(Pid, Message, Options) ->
    gen_fsm:send_event(Pid, {message, Message, Options}).

normal(Pid) ->
    gen_fsm:send_event(Pid, normal).

subscribe(Pid, Jid) ->
    gen_fsm:send_event(Pid, {add, Jid}).

% Send to every connected users
publish(Pid) ->
    gen_fsm:send_event(Pid, publish).

% Next question
next(Pid)->
    %gen_fsm:sync_send_event(Pid, next).
    gen_fsm:send_event(Pid, next).

% Current question
current(Pid) ->
    gen_fsm:sync_send_event(Pid, current).

% Get information about the game
info(Pid) ->
    gen_fsm:sync_send_event(Pid, info).

users(Pid) ->
    gen_fsm:sync_send_event(Pid, users).

stop(Pid) ->
	gen_fsm:send_all_state_event(Pid, stop).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init([ Id, Host, Creator, Ref, Module]) ->
    State = #state{
        roomid=Id,
            host=Host,
            roomref=Ref,
            creator=Creator,
            cid=newcid(),
            timeout=10000,
            mod=Module,
            users = gb_trees:empty(),
            inactivity_timeout = ?INACTIVITY_TIMEOUT 
    },
    prepare(undefined, State).

    %{ok, init, State, 0}.


handle_info(_Info, StateName, State) ->
    fsm_next_state(StateName, State).
  
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_event(cancel, _StateName, _State) ->
    {next_state, enroll, _State, ?INACTIVITY_TIMEOUT};

handle_event(stop, _StateName, State) ->
    {stop, normal, State};
  
handle_event(_Event, StateName, State) ->
    {next_state, StateName, State, ?INACTIVITY_TIMEOUT}.
  
handle_sync_event(_Event, _From, StateName, State) ->
    Reply = {error, undefined},
    {reply, Reply, StateName, State, ?INACTIVITY_TIMEOUT}.

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State, ?INACTIVITY_TIMEOUT}.

%% init/2
init(timeout, #state{ roomref=Fqid, creator=_Userid, users=Users } = State) ->
    case hyp_data:execute(hyd_fqids, read, [Fqid]) of
        {ok, Props} ->
            case hyp_data:extract([<<"api">>,<<"type">>], Props) of 
                undefined ->
                    {stop, enoent};
                Type ->
                    init(Type, State)
            end;

        {error, Error} ->
            {stop, Error}
    end;

init(Type, #state{ roomref=Fqid, creator=Userid, users=Users } = State) when 
    Type =:= <<"group">>;
    Type =:= <<"thread">> ->

    case hyp_data:action(Userid, Fqid, <<"members">>, []) of

        {ok, {_Infos, Subscriber}} when is_binary(Subscriber) ->
            NewUsers = gb_trees:enter(Subscriber, undefined, Users),
            fsm_next_state(normal, State#state{ users=NewUsers });

        {ok, {_Infos, Subscribers}} when is_list(Subscribers) ->
            NewUsers = lists:foldl( fun( Id, Tree ) ->
                gb_trees:enter(Id, undefined, Tree)
            end, Users, Subscribers),
            fsm_next_state(normal, State#state{ users=NewUsers });
    
        {error, Error} ->
            {stop, Error}
    end;

init(Type, #state{ roomref=Fqid,  creator=_Userid, users=Users } = State) when 
    Type =:= <<"drop">> ->

    case hyp_data:execute(hyd_fqids, read, [Fqid]) of
        {ok, Props} ->
            case hyp_data:extract([<<"info">>,<<"parent">>], Props) of 
                undefined ->
                    {stop, enoent};
                ParentFqid ->
                    NewState = State#state{ roomref=ParentFqid },
                    init(timeout, NewState)
            end;

        {error, Error} ->
            {stop, Error}
    end.



%% init/3
init(_, _, State) ->
    fsm_next_state(init, State).

%% STATE enroll
%% enroll/2
enroll(timeout, State) ->
    %error_msg(?MODULE_STRING " timeout in state 'enroll' roomref: ~p\n", [State#state.roomref]),
    {stop, normal, State};

enroll(normal, State) ->
    fsm_next_state(normal, State);

enroll(_Msg, State) ->
    ?ERROR_MSG("enroll/2: unknown message: ~p\n", [ _Msg ]),
    {next_state, enroll, State, ?INACTIVITY_TIMEOUT}.

%% enroll/3
enroll(_Msg, _, State) ->
    ?ERROR_MSG("enroll/3: unknown message: ~p\n", [ _Msg ]),
    {reply, undefined, enroll, State}.


%%normal/2
normal({add, Jid}, #state{ users=Users } = State) ->
	?DEBUG(?MODULE_STRING " normal: adding user ~p\n", [ Jid ]), 
    NewUsers = gb_trees:enter(Jid, undefined, Users),
    fsm_next_state(normal, State#state{ users=NewUsers });

normal({del, Jid}, #state{ users=Users } = State) ->
	?DEBUG(?MODULE_STRING " normal: deleting user ~p\n", [ Jid ]), 
    NewUsers = gb_trees:delete(Jid, Users),
    fsm_next_state(normal, State#state{ users=NewUsers });

normal({message, Message}, #state{ cid=Id } = State) ->
    ?DEBUG(?MODULE_STRING " normal: got message: ~p", [ Message ]),
    NewState = State#state{ cid = Id + 1 },
    send_message(Message, NewState),
    fsm_next_state(normal, NewState);

normal({info, Message}, State) ->
    ?DEBUG(?MODULE_STRING " normal: info message: ~p", [ Message ]),
    fsm_next_state(normal, State);

normal({message, Message, Opts}, #state{ cid=Id } = State) ->
    {NewState, _NewMessage} = handle_message(Message, Opts, State#state{ cid = Id + 1}),
    fsm_next_state(normal, NewState);

normal(timeout, State) ->
    ?DEBUG(?MODULE_STRING " normal: timeout, stopping\n", []),
    {stop, normal, State};
    
normal(_Msg, State) ->
    ?ERROR_MSG(?MODULE_STRING " normal/2: unknown message: ~p\n", [ _Msg ]),
    {next_state, normal, State, ?INACTIVITY_TIMEOUT}.

locked(_Msg, State) ->
    ?ERROR_MSG(?MODULE_STRING " locked/2: unknown message: ~p\n", [ _Msg ]),
    {next_state, locked, State, ?INACTIVITY_TIMEOUT}.

normal(_Msg, _, State) ->
    ?ERROR_MSG(?MODULE_STRING " normal/3: unknown message: ~p\n", [ _Msg ]),
    {reply, undefined, normal, State}.

locked(_Msg, _, State) ->
    ?ERROR_MSG(?MODULE_STRING " locked/3: unknown message: ~p\n", [ _Msg ]),
    {reply, undefined, locked, State}.

route(From, To, Message) ->
    io:format(?MODULE_STRING " Route: From ~p, To ~p, Message: ~p\n", [ From, To, Message ]).


-ifdef(test).
test() ->
	{ok, A} = start_link(1, ?MODULE, <<"Chatroom">>),
	J1 = <<"antoine@messaging.harmony">>,
	J2 = <<"thomas@messaging.harmony">>,
	%J1Hash = erlang:phash2( J1 ),
	%J2Hash = erlang:phash2( J2 ),
	normal(A),
	add(A, J1),
	add(A, J2),
	message(A, {message, <<"AWAKE ?">>}),
	receive after 1000 -> ok end,
	message(A, {message, <<"YES MASTER">>}),
	receive after 1000 -> ok end,
	Options = [{expire, 2000}],
	message(A, {message, <<"YES MASTER :(">>}, Options),
	io:format("Info: ~p\n", [ info(A) ]),
	%io:format("Score: ~p\n", [ score(A) ]),
	receive after 10000 -> ok end,
	stop(A).
-endif.

% transaction(Fun) ->
% 	case mnesia:transaction(Fun) of
% 		{atomic, []} ->
% 			{ok, enoent};
% 		{aborted, Reason} ->
% 			?ERROR_MSG("Transaction error: ~p\n", [ Reason ]),
% 			{error, Reason};
% 		{atomic, Any} ->
% 			%info_msg("Atomic: ~p\n", [ Any ]),
% 			{ok, Any};
% 		_A ->
% 			%info_msg("Transaction: ~p\n", [ _A ]),
% 			_A
% 	end.

% hash(GameId, JidHash) ->
% 	erlang:phash2([ GameId, JidHash ]).

%% FIXME Message should be split to only content and ignore signaling info;
%% from, to, type
%% Purpose Id must be incorporated in the final packet sent to users
send_message(Message, #state{ roomref=Ref, host=Host, mod=Module, users=Users, cid=Id } = _State) ->
    Jids = gb_trees:keys(Users),
    lists:foreach( fun( User ) ->
        To = iolist_to_binary([User,<<"@">>,Host]),
        From = iolist_to_binary([<<"chat@harmony/">>, Ref]),
        Msgid = iolist_to_binary([Ref, $. , integer_to_list(Id)]),
        Packet = {chat, {Msgid, Message}},
        ?DEBUG(?MODULE_STRING " send_message: Module: ~p from: ~p to: ~p\n~p\n", [ Module, From, To, Packet ]), 
        Module:route(From, To, Packet )
    end, Jids).

fsm_next_state(StateName, #state{ inactivity_timeout = Timeout } = State) ->
    {next_state, StateName, State, Timeout}.

newcid() ->
    Now = os:timestamp(),
    %CountryCode = "33",
    %Cid = CountryCode ++ lists:concat(tuple_to_list(Now)),
    Cid = lists:concat(tuple_to_list(Now)),
    list_to_integer(Cid).

handle_message( Message, Opts, State) ->
    {NewState, NewMessage} = options(State, Message, Opts),
    send_message(NewMessage, NewState),
    {NewState, NewMessage}.

options(State, Message, [] ) ->
    {State, Message};
options(State, Message, [{expire, Timer}| Options ]) ->
    gen_fsm:send_event_after(Timer, {delete, State#state.cid}),
    options(State,Message, Options);
options(State, Message, [ _| Options]) ->
    options(State, Message, Options).

% get_from_packet(type, {struct, [{Type, _}]}) ->
%     Type;
% get_from_packet(args, {struct, [{_Type, {struct, Args}} |_ ]}) ->
%     Args;
% get_from_packet(_What, _Packet) ->
%     [].


%% prepare/2
prepare(undefined, #state{ roomref=Fqid, creator=_Userid, users=Users } = State) ->
    case hyp_data:execute(hyd_fqids, read, [Fqid]) of
        {ok, Props} ->
            case hyp_data:extract([<<"api">>,<<"type">>], Props) of 
                undefined ->
                    {stop, enoent};
                Type ->
                    prepare(Type, State)
            end;

        {error, Error} ->
            {stop, Error}
    end;

prepare(Type, #state{ roomref=Fqid, creator=Userid, users=Users } = State) when 
    Type =:= <<"group">>;
    Type =:= <<"thread">> ->

    case hyp_data:action(Userid, Fqid, <<"members">>, []) of

        {ok, {_Infos, Subscriber}} when is_binary(Subscriber) ->
            NewUsers = gb_trees:enter(Subscriber, undefined, Users),
            {ok, normal, State#state{ users=NewUsers }};

        {ok, {_Infos, Subscribers}} when is_list(Subscribers) ->
            NewUsers = lists:foldl( fun( Id, Tree ) ->
                gb_trees:enter(Id, undefined, Tree)
            end, Users, Subscribers),
            {ok, normal, State#state{ users=NewUsers }};
    
        {error, Error} ->
            {stop, Error}
    end;

prepare(Type, #state{ roomref=Fqid,  creator=_Userid, users=Users } = State) when 
    Type =:= <<"drop">> ->

    case hyp_data:execute(hyd_fqids, read, [Fqid]) of
        {ok, Props} ->
            case hyp_data:extract([<<"info">>,<<"parent">>], Props) of 
                undefined ->
                    {stop, enoent};
                ParentFqid ->
                    NewState = State#state{ roomref=ParentFqid },
                    prepare(undefined, NewState)
            end;

        {error, Error} ->
            {stop, Error}
    end;

prepare(Type, #state{ roomref=Fqid,  creator=_Userid, users=Users } = State) ->
    ?DEBUG( ?MODULE_STRING "[~5w] Unhandled live process for type: ~p", [ ?LINE, Type ]),
    {stop, einval}.

