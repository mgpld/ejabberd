-module(hyp_notify).
% Created hyp_notify.erl the 08:34:29 (03/09/2016) on core
% Last Modification of hyp_notify.erl at 15:21:37 (03/09/2016) on core
% 
% Author: "rolph" <rolphin@free.fr>

-behaviour(gen_fsm).

-include("ejabberd.hrl").
-include("logger.hrl").

-export([
    start/1,start/3,
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


%-define(test, true).

-ifdef(test).
-export([
    debug_link/1
]).
-endif.

% fsm states
-export([
    normal/2, normal/3,
    locked/2, locked/3
]).

-define( INACTIVITY_TIMEOUT, 10 * 1000). % 10 seconds
-define( DELAY_TIMEOUT, 1 * 1000). % 1 second

-record(question, {
    id,
    title,
    answers,
    answer
}).

-record(state,{
    type,
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


start_link(Type, Module, RoomRef ) ->
    gen_fsm:start_link(?MODULE, [Type, Module, RoomRef], []).

start_link(Type, Host, Creator, RoomRef, Module ) ->
    gen_fsm:start_link(?MODULE, [Type, Host, Creator, RoomRef, Module], []).

start_link(Type) ->
    gen_fsm:start_link(?MODULE, [Type], []).

start(Type) ->
    gen_fsm:start(?MODULE, [Type], []).

start(Type, Module, RoomRef ) ->
    gen_fsm:start(?MODULE, [Type, Module, RoomRef], []).

start_link() ->
    gen_fsm:start_link(?MODULE, ?MODULE, [], []).

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
init([ Type, Host, Creator, Ref, Module]) ->
    State = #state{
        type=Type,
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

handle_info(_Info, StateName, State) ->
    fsm_next_state(StateName, State).
  
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_event(cancel, _StateName, _State) ->
    {next_state, normal, _State, ?INACTIVITY_TIMEOUT};

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
    ?DEBUG(?MODULE_STRING "[~5w] normal: got message: ~p", [ ?LINE, Message ]),
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
    %send_message(<<"test notify">>, State),
    ?DEBUG(?MODULE_STRING " normal: work completed, stopping\n", []),
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

%% FIXME Message should be split to only content and ignore signaling info;
%% from, to, type
%% Purpose Id must be incorporated in the final packet sent to users
send_message(Message, #state{ roomref=Ref, users=Users, cid=Id } = State) ->
    Child = hyp_data:extract([<<"message">>,<<"child">>], Message),
    From = iolist_to_binary([<<"event@harmony/">>, Ref]),
    Msgid = iolist_to_binary([Ref, $. , integer_to_list(Id)]),
    Iter = gb_trees:iterator(Users),
    Tree = gb_trees:next(Iter),
    publish(Tree, Child, Msgid, From, Message, State).

fsm_next_state(StateName, #state{ inactivity_timeout = Timeout } = State) ->
    {next_state, StateName, State, Timeout}.

newcid() ->
    Now = os:timestamp(),
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
prepare(undefined, #state{ roomref=Fqid, creator=_Userid, users=_Users } = State) ->
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
    Type =:= <<"comgroup">>;
    Type =:= <<"thread">>;
    Type =:= <<"group">>;
    Type =:= <<"page">> ->

    case hyp_data:action(Userid, Fqid, <<"members">>, []) of

        {ok, {_Infos, Subscribers}} when is_list(Subscribers) ->
            NewUsers = lists:foldl( fun( Id, Tree ) ->
                gb_trees:enter(Id, Type, Tree)
                %case db:call(<<"%getNotificationGroup">>,<<"users">>, [Id]) of
                %    {ok, Notifygroup} ->
                %        ?DEBUG(?MODULE_STRING "[~5w] getNotificationGroup: Id: ~p Newsfeed: ~p", [ ?LINE, Id, Notifygroup ]), 
                %        gb_trees:enter(Id, Notifygroup, Tree);
                %    _ ->
                %        ok
                %end
            end, Users, Subscribers),
            {ok, normal, State#state{ users=NewUsers }, ?INACTIVITY_TIMEOUT};
        
        {ok, _} ->
            {stop, normal};
    
        {error, Error} ->
            {stop, Error}
    end;

% Search for user contacts, retrieve contact's timeline 
% Notify every contacts that the user has updated his timeline ?
prepare(Type, #state{ roomref=_Fqid, creator=Userid, users=Users } = State) when
    Type =:= <<"timeline">> ->
    case hyd_users:contacts(Userid) of
        [] ->
            {stop, normal};

        {error, Error} ->
            {stop, Error};
        
        Contacts ->
            NewUsers = lists:foldl( fun( Id, Tree ) ->
                case db:call(<<"%getNotificationGroup">>,<<"users">>, [Id]) of
                    {ok, Newsfeed} ->
                        ?DEBUG(?MODULE_STRING "[~5w] getNotificationGroup: Id: ~p Newsfeed: ~p", [ ?LINE, Id, Newsfeed ]), 
                        gb_trees:enter(Id, Newsfeed, Tree);
                    _ ->
                        ok
                end
            end, Users, Contacts),
            {ok, normal, State#state{ users=NewUsers }, ?DELAY_TIMEOUT}

    end;

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
    end.

% send_message(Message, #state{ roomref=Ref, host=Host, mod=Module, users=Users, cid=Id } = _State) ->

% 1) store message in user newsfeed 
% 2) send realtime message about this new message
publish(none, _, _, _, _, _) ->
    ok;
publish({User, Type, Iter}, Child, Msgid, From, Message, #state{ host=Host, mod=Module } = State) ->
    To = iolist_to_binary([User,<<"@">>,Host]),
    Packet = {notification, {Msgid, Message}},
    Token = iolist_to_binary([<<"com.harmony.">>, application(Type) ]),
    Class = hyp_data:extract([<<"message">>, <<"type">>], Message),
    Sender = hyp_data:extract([<<"message">>, <<"from">>, <<"id">>], Message),
    Title = <<"activity">>,
    Content = <<>>,
    Args = [ Sender, Class, Child, User, Token, Title, Content ],
    ?DEBUG(?MODULE_STRING "[~5w] send_notification: args ~p", [ ?LINE, Args ]),
    % NOTIFICATIONS
    hyd_fqids:action(<<"notification">>, <<"create">>, Args), % synchronous
    %addchild(Notifygroup, User, Child),
    ?DEBUG(?MODULE_STRING "[~5w] send_message: Module: ~p from: ~p to: ~p", [ ?LINE, Module, From, To ]), 
    Module:route(From, To, Packet ), % realtime notification
    publish(gb_trees:next(Iter), Child, Msgid, From, Message, State).

addchild(<<"0">>, _User, _Child) ->
    ok;
addchild(Notifygroup, User, Child) ->
    hyd_fqids:action(Notifygroup, <<"addChild">>, [ User, Child ]).


application(<<"drop">>) -> <<"hychat">>;
application(<<"page">>) -> <<"community">>;
application(<<"group">>) -> <<"hychat">>;
application(<<"thread">>) -> <<"hychat">>;
application(<<"comgroup">>) -> <<"community">>;
application(<<"timeline">>) -> <<"community">>;
application(_App) ->  _App.
