-module(hyp_live).
% Created hyp_live.erl the 13:33:37 (01/01/2015) on core
% Last Modification of hyp_live.erl at 14:36:05 (03/09/2016) on core
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
    enroll/2, enroll/3,
    normal/2, normal/3,
    init/2, init/3,
    locked/2, locked/3
]).

% -define( UINT16(X),	X:16/native-unsigned).
%-define( INACTIVITY_TIMEOUT, 5 * 60000). % 5 minutes
-define( INACTIVITY_TIMEOUT, 60 * 1000). % 10 seconds

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
    last,
    cid,
    mod, % module must implement route/4
    timeout, % timeout between questions
    question = #question{},
    users,
    inactivity_timeout,
    notify % notification process
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
    Now = os:timestamp(),
    State = #state{
        roomid=Id,
        host=Host,
        roomref=Ref,
        last=Now,
        creator=Creator,
        cid=newcid(Now),
        timeout=10000,
        mod=Module,
        users = gb_trees:empty(),
        inactivity_timeout = ?INACTIVITY_TIMEOUT,
        notify=undefined
    },
    prepare(undefined, State).



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

%% init/2
init(timeout, #state{
    roomid=RoomId, 
    host=ServerHost, 
    creator=Creator,
    roomref=RoomRef,
    mod=Module
    } = State) ->
    case hyp_notify:start_link(RoomId, ServerHost, Creator, RoomRef, Module) of
        {ok, Pid} ->
            ?DEBUG(?MODULE_STRING "[~5w] HYP_LIVE: Notify process ok pid ~p roomref: ~p mod: ~p", [ ?LINE, Pid, RoomRef, Module]),
            fsm_next_state(normal, State#state{ notify=Pid });

        {error, Reason} ->
            ?ERROR_MSG(?MODULE_STRING "[~5w] HYP_LIVE: Notify FAIL create new room for type ~p (~p) mod: ~p", [ ?LINE, RoomRef, RoomId, Module]),
            {stop, normal, State}
    end;

init(_, State) ->
    fsm_next_state(init, State).

%% init/3
init(_Msg, _, State) ->
    ?ERROR_MSG(?MODULE_STRING " init/3: unknown message: ~p", [ _Msg ]),
    {noreply, init, State}.

%%normal/2
normal({add, Jid}, #state{ users=Users } = State) ->
	?DEBUG(?MODULE_STRING " normal: adding user ~p\n", [ Jid ]), 
    NewUsers = gb_trees:enter(Jid, undefined, Users),
    fsm_next_state(normal, State#state{ users=NewUsers });

normal({del, Jid}, #state{ users=Users } = State) ->
	?DEBUG(?MODULE_STRING " normal: deleting user ~p\n", [ Jid ]), 
    NewUsers = gb_trees:delete(Jid, Users),
    fsm_next_state(normal, State#state{ users=NewUsers });

% Only execute notification for the first message
normal({message, Message}, #state{ cid=Id, notify=Notify } = State) when is_pid(Notify) ->
    ?DEBUG(?MODULE_STRING " normal: got message: ~p", [ Message ]),
    Now = os:timestamp(),
    NewState = State#state{ cid = Id + 1, last = Now, notify = undefined },
    send_message(Message, NewState),
    fsm_next_state(normal, NewState);

normal({message, Message}, #state{ cid=Id } = State) ->
    ?DEBUG(?MODULE_STRING " normal: got message: ~p", [ Message ]),
    Now = os:timestamp(),
    NewState = State#state{ cid = Id + 1, last = Now },
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

%% normal/3
normal(_Msg, _, State) ->
    ?ERROR_MSG(?MODULE_STRING " normal/3: unknown message: ~p\n", [ _Msg ]),
    {reply, undefined, normal, State}.

%% locked/3
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

%% FIXME Message should be split to only content and ignore signaling info;
%% from, to, type
%% Purpose Id must be incorporated in the final packet sent to users
send_message(Message, #state{ roomref=Ref, users=Users, cid=Id, last=Last, notify=Notify } = State) ->
    From = iolist_to_binary([<<"chat@harmony/">>, Ref]),
    Msgid = iolist_to_binary([Ref, $. , integer_to_list(Id)]),
    Iter = gb_trees:iterator(Users),
    publish(gb_trees:next(Iter), Msgid, From, Message, State),
    notify(Message, State).

notify(Message, #state{ notify=Notify }) when is_pid(Notify) ->
    hyp_notify:message(Notify, Message);
notify(Message, #state{ notify=_ }) ->
    ok.

    % % FIXME if the room is not running, how to retrieve the last timestamp ?
    % % Maybe a notification must only be sent the moment this process is recreated...
    % Now = os:timestamp(), % if more than 50 seconds old, notify users
    % case (timer:now_diff(Last,Now) div 1000) > 50000 of
    %     true ->
    %         Iter = gb_trees:iterator(Users),
    %         notify(gb_trees:next(Iter), Msgid, From, Message, State);

    %     false ->
    %         ok
    % end.

% send_message(Message, #state{ roomref=Ref, host=Host, mod=Module, users=Users, cid=Id } = _State) ->
%     Jids = gb_trees:keys(Users),
%     lists:foreach( fun( User ) ->
%         To = iolist_to_binary([User,<<"@">>,Host]),
%         From = iolist_to_binary([<<"chat@harmony/">>, Ref]),
%         Msgid = iolist_to_binary([Ref, $. , integer_to_list(Id)]),
%         Packet = {chat, {Msgid, Message}},
%         ?DEBUG(?MODULE_STRING " send_message: Module: ~p from: ~p to: ~p\n~p\n", [ Module, From, To, Packet ]), 
%         Module:route(From, To, Packet )
%     end, Jids).
% 
fsm_next_state(StateName, #state{ inactivity_timeout = Timeout } = State) ->
    {next_state, StateName, State, Timeout}.

newcid(Now) ->
    %Now = os:timestamp(),
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

%% prepare/2
prepare(undefined, #state{ roomref=Fqid, creator=_Userid } = State) ->
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
            {ok, init, State#state{ users=NewUsers }, 0};

        {ok, {_Infos, Subscribers}} when is_list(Subscribers) ->
            NewUsers = lists:foldl( fun( Id, Tree ) ->
                gb_trees:enter(Id, undefined, Tree)
            end, Users, Subscribers),
            {ok, init, State#state{ users=NewUsers }, 0};
    
        {error, Error} ->
            {stop, Error}
    end;

% inform the parent (owner) of this drop that a new element has been added
prepare(Type, #state{ roomref=Fqid,  creator=_Userid } = State) when 
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

prepare(Type, _State) ->
    ?DEBUG( ?MODULE_STRING "[~5w] Unhandled live process for type: ~p", [ ?LINE, Type ]),
    {stop, einval}.

% send realtime message about this new message
publish(none, _, _, _, _) ->
    ok;
publish({User, _, Iter}, Msgid, From, Message, #state{ host=Host, mod=Module } = State) ->
    To = iolist_to_binary([User,<<"@">>,Host]),
    Packet = {chat, {Msgid, Message}},
    ?DEBUG(?MODULE_STRING "[~5w] send_message: Module: ~p from: ~p to: ~p", [ ?LINE, Module, From, To ]), 
    Module:route(From, To, Packet ),
    publish(gb_trees:next(Iter), Msgid, From, Message, State).

% create notification if needed (compute elapsed time to prevent spamming)
notify(none, _, _, _, _) ->
    ok;
notify({User, _, Iter}, Msgid, From, Message, #state{ host=Host, mod=Module} = State) ->
    To = iolist_to_binary([User,<<"@">>,Host]),
    Packet = {chat, {Msgid, Message}},
    ?DEBUG(?MODULE_STRING "[~5w] notify: Module: ~p from: ~p to: ~p", [ ?LINE, Module, From, To ]), 
    notify(gb_trees:next(Iter), Msgid, From, Message, State).

