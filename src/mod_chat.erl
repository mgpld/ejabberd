%%%----------------------------------------------------------------------
%%% File    : mod_chat.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : MUC support (XEP-0045)
%%% Created : 19 Mar 2003 by Alexey Shchepin <alexey@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2013   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(mod_chat).

-author('mgpld@free.fr').

-behaviour(gen_server).
-behaviour(gen_mod).

%% API
-export([
    start/2,
    start_link/2,
    stop/1,
    route/3, route/5,
    room_destroyed/4,
    store_room/4,
    restore_room/3,
    forget_room/3,
    create_room/5,
    shutdown_rooms/1,
    process_iq_disco_items/4,
    broadcast_service_message/2,
    export/1,
    import/1,
    import/3,
    can_use_nick/4]).

-export([
    existing_room/2,
    string_to_jid/1
]).

-export([
    test/0
]).

%% gen_server callbacks
-export([
    init/1, 
    handle_call/3, 
    handle_cast/2,
    handle_info/2, 
    terminate/2, 
    code_change/3]).

-include("ejabberd.hrl").
-include("logger.hrl").

-include("jlib.hrl").

-record(muc_room, {name_host = {<<"">>, <<"">>} :: {binary(), binary()} |
                                                   {'_', binary()},
                   opts = [] :: list() | '_'}).

-record(muc_online_room,
        {name_host = {<<"">>, <<"">>} :: {binary(), binary()} | '$1' |
                                         {'_', binary()} | '_',
         pid = self() :: pid() | '$2' | '_' | '$1'}).

-record(muc_registered,
        {us_host = {{<<"">>, <<"">>}, <<"">>} :: {{binary(), binary()}, binary()} | '$1',
         nick = <<"">> :: binary()}).

-record(state, {
    host = <<"">> :: binary(),
    server_host = <<"">> :: binary(),
    access = {none, none, none, none} :: {atom(), atom(), atom(), atom()},
    history_size = 20 :: non_neg_integer(),
    default_room_opts = [] :: list(),
    timeout = 5000 :: integer(),
    room_shaper = none :: shaper:shaper()}).

% h(armony)_multi_user_conference
-define(PROCNAME, h_muc).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Host, Opts) ->
    Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
    gen_server:start_link({local, Proc}, ?MODULE,
            [Host, Opts], []).

start(Host, Opts) ->
    start_supervisor(Host),
    Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
    ChildSpec = {Proc, {?MODULE, start_link, [Host, Opts]},
        transient, 1000, worker, [?MODULE]},
    supervisor:start_child(ejabberd_sup, ChildSpec).

stop(Host) ->
    Rooms = shutdown_rooms(Host),
    stop_supervisor(Host),
    Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
    gen_server:call(Proc, stop),
    supervisor:delete_child(ejabberd_sup, Proc),
    {wait, Rooms}.

shutdown_rooms(Host) ->
    MyHost = gen_mod:get_module_opt_host(Host, mod_muc,
            <<"conference.@HOST@">>),
    Rooms = mnesia:dirty_select(muc_online_room,
            [{#muc_online_room{name_host = '$1',
            pid = '$2'},
            [{'==', {element, 2, '$1'}, MyHost}],
            ['$2']}]),
    [Pid ! shutdown || Pid <- Rooms],
    Rooms.

%% This function is called by a room in three situations:
%% A) The owner of the room destroyed it
%% B) The only participant of a temporary room leaves it
%% C) mod_muc:stop was called, and each room is being terminated
%%    In this case, the mod_muc process died before the room processes
%%    So the message sending must be catched
room_destroyed(Host, Room, Pid, ServerHost) ->
    catch gen_mod:get_module_proc(ServerHost, ?PROCNAME) ! {room_destroyed, {Room, Host}, Pid},
    ok.

%% @doc Create a room.
%% If Opts = default, the default room options are used.
%% Else use the passed options as defined in mod_muc_room.
create_room(Host, RoomId, From, RoomRef, Opts) ->
    Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
    gen_server:call(Proc, {create, RoomId, From, RoomRef, Opts}).

% create_room(<<"messaging.harmony">>, 1, undefined, <<"abcd">>, []).

route(Host, RoomId, From, Function, Args) ->
    Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
    Proc ! {route, RoomId, From, Function, Args}.

% Called by the chat_master process
route(From, ToJid, Message) when is_tuple(ToJid) ->
    FromJid = string_to_jid(From),
    ejabberd_router:route(FromJid, ToJid, Message);

route(From, To, Message) ->
    FromJid = string_to_jid(From),
    ToJid = string_to_jid(To),
    ejabberd_router:route(FromJid, ToJid, Message).

store_room(ServerHost, Host, Name, Opts) ->
    LServer = jlib:nameprep(ServerHost),
    store_room(LServer, Host, Name, Opts,
	       gen_mod:db_type(LServer, ?MODULE)).

store_room(_LServer, Host, Name, Opts, mnesia) ->
    F = fun () ->
		mnesia:write(#muc_room{name_host = {Name, Host},
				       opts = Opts})
	end,
    mnesia:transaction(F);
store_room(LServer, Host, Name, Opts, odbc) ->
    SName = ejabberd_odbc:escape(Name),
    SHost = ejabberd_odbc:escape(Host),
    SOpts = ejabberd_odbc:encode_term(Opts),
    F = fun () ->
		odbc_queries:update_t(<<"muc_room">>,
				      [<<"name">>, <<"host">>, <<"opts">>],
				      [SName, SHost, SOpts],
				      [<<"name='">>, SName, <<"' and host='">>,
				       SHost, <<"'">>])
	end,
    ejabberd_odbc:sql_transaction(LServer, F).

restore_room(ServerHost, Host, Name) ->
    LServer = jlib:nameprep(ServerHost),
    restore_room(LServer, Host, Name,
                 gen_mod:db_type(LServer, ?MODULE)).

restore_room(_LServer, Host, Name, mnesia) ->
    case catch mnesia:dirty_read(muc_room, {Name, Host}) of
      [#muc_room{opts = Opts}] -> Opts;
      _ -> error
    end;
restore_room(LServer, Host, Name, odbc) ->
    SName = ejabberd_odbc:escape(Name),
    SHost = ejabberd_odbc:escape(Host),
    case catch ejabberd_odbc:sql_query(LServer,
				       [<<"select opts from muc_room where name='">>,
					SName, <<"' and host='">>, SHost,
					<<"';">>])
	of
      {selected, [<<"opts">>], [[Opts]]} ->
	  opts_to_binary(ejabberd_odbc:decode_term(Opts));
      _ -> error
    end.

forget_room(ServerHost, Host, Name) ->
    LServer = jlib:nameprep(ServerHost),
    forget_room(LServer, Host, Name,
		gen_mod:db_type(LServer, ?MODULE)).

forget_room(_LServer, Host, Name, mnesia) ->
    F = fun () -> mnesia:delete({muc_room, {Name, Host}})
	end,
    mnesia:transaction(F);
forget_room(LServer, Host, Name, odbc) ->
    SName = ejabberd_odbc:escape(Name),
    SHost = ejabberd_odbc:escape(Host),
    F = fun () ->
		ejabberd_odbc:sql_query_t([<<"delete from muc_room where name='">>,
					   SName, <<"' and host='">>, SHost,
					   <<"';">>])
	end,
    ejabberd_odbc:sql_transaction(LServer, F).

process_iq_disco_items(Host, From, To,
		       #iq{lang = Lang} = IQ) ->
    Rsm = jlib:rsm_decode(IQ),
    Res = IQ#iq{type = result,
		sub_el =
		    [#xmlel{name = <<"query">>,
			    attrs = [{<<"xmlns">>, ?NS_DISCO_ITEMS}],
			    children = iq_disco_items(Host, From, Lang, Rsm)}]},
    ejabberd_router:route(To, From, jlib:iq_to_xml(Res)).

can_use_nick(_ServerHost, _Host, _JID, <<"">>) -> false;
can_use_nick(ServerHost, Host, JID, Nick) ->
    LServer = jlib:nameprep(ServerHost),
    can_use_nick(LServer, Host, JID, Nick,
		 gen_mod:db_type(LServer, ?MODULE)).

can_use_nick(_LServer, Host, JID, Nick, mnesia) ->
    {LUser, LServer, _} = jlib:jid_tolower(JID),
    LUS = {LUser, LServer},
    case catch mnesia:dirty_select(muc_registered,
				   [{#muc_registered{us_host = '$1',
						     nick = Nick, _ = '_'},
				     [{'==', {element, 2, '$1'}, Host}],
				     ['$_']}])
	of
      {'EXIT', _Reason} -> true;
      [] -> true;
      [#muc_registered{us_host = {U, _Host}}] -> U == LUS
    end;
can_use_nick(LServer, Host, JID, Nick, odbc) ->
    SJID =
	jlib:jid_to_string(jlib:jid_tolower(jlib:jid_remove_resource(JID))),
    SNick = ejabberd_odbc:escape(Nick),
    SHost = ejabberd_odbc:escape(Host),
    case catch ejabberd_odbc:sql_query(LServer,
				       [<<"select jid from muc_registered ">>,
					<<"where nick='">>, SNick,
					<<"' and host='">>, SHost, <<"';">>])
	of
      {selected, [<<"jid">>], [[SJID1]]} -> SJID == SJID1;
      _ -> true
    end.

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([Host, Opts]) ->
    MyHost = gen_mod:get_opt_host(Host, Opts, <<"conference.@HOST@">>),
    case gen_mod:db_type(Opts) of
        mnesia ->
            mnesia:create_table(muc_room,
                                [{disc_copies, [node()]},
                                 {attributes,
                                  record_info(fields, muc_room)}]),
            mnesia:create_table(muc_registered,
                                [{disc_copies, [node()]},
                                 {attributes,
                                  record_info(fields, muc_registered)}]),
            update_tables(MyHost);
            %mnesia:add_table_index(muc_registered, nick);
        _ ->
            ok
    end,
    mnesia:create_table(muc_online_room, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, muc_online_room)}]),
    mnesia:add_table_copy(muc_online_room, node(), ram_copies),
    catch ets:new(muc_online_users, [bag, named_table, public, {keypos, 2}]),
    clean_table_from_bad_node(node(), MyHost),
    mnesia:subscribe(system),

    IdentFun = fun(A) -> A end,
    Access = gen_mod:get_opt(access, Opts, fun(A) -> A end, all),
    AccessCreate = gen_mod:get_opt(access_create, Opts, fun(A) -> A end, all),
    AccessAdmin = gen_mod:get_opt(access_admin, Opts, fun(A) -> A end, none),
    AccessPersistent = gen_mod:get_opt(access_persistent, Opts, fun(A) -> A end, all),
    HistorySize = gen_mod:get_opt(history_size, Opts, fun(A) -> A end, 20),
    DefRoomOpts = gen_mod:get_opt(default_room_options, Opts, fun(A) -> A end, []),
    RoomShaper = gen_mod:get_opt(room_shaper, Opts, fun(A) -> A end, none),
    GameConfig = gen_mod:get_opt(game, Opts, IdentFun, undefined),
    Timeout = gen_mod:get_opt(timeout, Opts, IdentFun, undefined),
%    ejabberd_router:register_route(MyHost),
%    load_permanent_rooms(MyHost, Host,
%			 {Access, AccessCreate, AccessAdmin, AccessPersistent},
%			 HistorySize,
%			 RoomShaper),
%    application:set_env(game, datalink, GameConfig),
    % Catch the end of games
    process_flag(trap_exit, true), 
    {ok, #state{host = MyHost,
		server_host = Host,
		timeout = Timeout,
		access = {Access, AccessCreate, AccessAdmin, AccessPersistent},
		default_room_opts = DefRoomOpts,
		history_size = HistorySize,
		room_shaper = RoomShaper}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

% {type, write} means that that hyd_storage will store data
handle_call({create, {type, write}, From, RoomRef, Opts}, _From,
    #state{host = Host, server_host = ServerHost,
        access = _Access, default_room_opts = DefOpts,
        history_size = _HistorySize,
        room_shaper = _RoomShaper} = State) ->
    
    IdentFun = fun(A) -> A end,
    Module = gen_mod:get_opt(module, Opts, IdentFun, ?MODULE),
    ?DEBUG("MUC: create new persistent(write) room '~s' mod: ~p", [RoomRef, Module]),
    Creator = From,
    {ok, Pid} = muc_room_persist:start_link(undefined, Creator, RoomRef, Module),
    muc_room_persist:normal(Pid), % going to normal mode 
    register_room(Host, RoomRef, Pid),
    {reply, ok, State};

handle_call({create, Type, From, RoomRef, Opts}, _From,
    #state{host = Host, server_host = ServerHost} = State) when
    Type =:= <<"timeline">>;
    Type =:= <<"comgroup">>;
    Type =:= <<"page">> ->

    case existing_room(Host, RoomRef) of
        false ->
            IdentFun = fun(A) -> A end,
            Module = gen_mod:get_opt(module, Opts, IdentFun, ?MODULE),
            ?DEBUG(?MODULE_STRING "[~5w] HYP_PERSIST: create new room from user ~p: '~s' (~p) mod: ~p", [ ?LINE, From, RoomRef, Type, Module]),
            case hyp_persist:start_link(Type, ServerHost, From, RoomRef, Module) of
                {ok, Pid} ->
                    register_room(Host, RoomRef, Pid),
                    {reply, ok, State};

                {error, _} -> %the persisting room is not needed because no subscribers
                    {reply, ok, State}
            end;

        {ok, _Pid} ->
            {reply, ok, State}
    end;

handle_call({create, RoomId, From, RoomRef, Opts}, _From,
    #state{host = Host, server_host = ServerHost,
        access = _Access, default_room_opts = _DefOpts,
        history_size = _HistorySize,
        room_shaper = _RoomShaper} = State) ->

    case existing_room(Host, RoomRef) of
        false ->
            IdentFun = fun(A) -> A end,
            Module = gen_mod:get_opt(module, Opts, IdentFun, ?MODULE),
            ?DEBUG(?MODULE_STRING " HYP_LIVE: create new room from user ~p: '~s' (~p) mod: ~p", [ From, RoomRef, RoomId, Module]),
            case hyp_live:start_link(RoomId, ServerHost, From, RoomRef, Module) of
                {ok, Pid} ->
                    register_room(Host, RoomRef, Pid),
                    {reply, ok, State};

                {error, Reason} = Error ->
                    ?ERROR_MSG(?MODULE_STRING "[~5w] HYP_LIVE: FAIL create new room for type ~p (~p) mod: ~p", [ ?LINE, RoomRef, RoomId, Module]),
                    {reply, Error, State}

            end;

        {ok, _Pid} ->
            {reply, ok, State}
    end.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast({create, RoomType, From, RoomRef, Opts}, #state{
        host = Host, server_host = ServerHost} = State) ->

    Module = ?MODULE,
    ?DEBUG(?MODULE_STRING ".~p HYP_LIVE: create new room from user ~p: '~s' (~p) mod: ~p", [ ?LINE, From, RoomRef, RoomType, Module]),
    {ok, Pid} = hyp_live:start_link(RoomType, ServerHost, From, RoomRef, Module),
    register_room(Host, RoomRef, Pid),
    {noreply, State};

handle_cast({create, {type, write}, Creator, RoomRef, Operations}, 
    #state{host = Host, server_host = _ServerHost,
        access = _Access, default_room_opts = _DefOpts,
        history_size = _HistorySize,
        room_shaper = _RoomShaper} = State) ->
    
    IdentFun = fun(A) -> A end,
    Module = gen_mod:get_opt(module, _DefOpts, IdentFun, ?MODULE),
    ?DEBUG("MUC: create new persistent(write) room '~s' mod: ~p", [RoomRef, Module]),
    {ok, Pid} = muc_room_persist:start_link(undefined, Creator, RoomRef, Module),
    muc_room_persist:normal(Pid), % going to normal mode 
    register_room(Host, RoomRef, Pid),
    case Operations of
        [] ->
            {noreply, State};
	
        {Function, Args} ->
            ?DEBUG(?MODULE_STRING " Room (just created): send to process ~p ~p ~p\n", [Pid, Function, Args]),
            apply(muc_room_persist, Function, [ Pid | Args ]),
            {noreply, State}
    end;
	
handle_cast(_Msg, State) -> 
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({route, GameId, From, Function, Args},
    #state{host = Host, server_host = ServerHost} = State) ->

    ?DEBUG(?MODULE_STRING " route: chatid: ~p From: ~p Function: ~p\n~p", [ GameId, From, Function, Args ]),
    case catch do_route(Host, ServerHost, From, GameId, Function, Args) of
        {'EXIT', Reason} ->
            ?ERROR_MSG(?MODULE_STRING " route error: ~p", [Reason]),
            {noreply, State};
        _ ->
            {noreply, State}
    end;

% Game has stopped, do cleanup
handle_info({room_destroyed, RoomHost, Pid}, State) ->
    F = fun () ->
        mnesia:delete_object(#muc_online_room{name_host =
            RoomHost,
            pid = Pid})
    end,
    mnesia:transaction(F),
    {noreply, State};

handle_info({mnesia_system_event, {mnesia_down, Node}}, State) ->
    clean_table_from_bad_node(Node),
    {noreply, State};

%handle_info(timeout, State) ->
%    game_master:next(Pid), 

handle_info({'EXIT', Pid, Reason}, State) ->
    F = fun() ->
        Es = mnesia:select( muc_online_room,
                [{#muc_online_room{pid = '$1', _ = '_'},
                    [{'==', '$1', Pid}],
                    ['$_']}
                ]),
        lists:foreach(fun(E) ->
            #muc_online_room{name_host = GameRef } = E,
            ?INFO_MSG(?MODULE_STRING " Unregistering chat pid: ~p: Ref: ~p reason: ~p", [ Pid, GameRef, Reason ]),
            mnesia:delete_object(E)
        end, Es)
    end,
    mnesia:transaction(F),
    {noreply, State};
    
handle_info(_Info, State) -> 
    ?DEBUG(?MODULE_STRING " Unhandled info: ~p", [ _Info ]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    %ejabberd_router:unregister_route(State#state.host),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
start_supervisor(Host) ->
%    Proc = gen_mod:get_module_proc(Host,
%				   ejabberd_mod_muc_sup),
%    ChildSpec = {Proc,
%		 {ejabberd_tmp_sup, start_link, [Proc, mod_muc_room]},
%		 permanent, infinity, supervisor, [ejabberd_tmp_sup]},
%    supervisor:start_child(ejabberd_sup, ChildSpec).
%
    ok.

stop_supervisor(Host) ->
    %Proc = gen_mod:get_module_proc(Host,
    %    			   ejabberd_mod_muc_sup),
    %supervisor:terminate_child(ejabberd_sup, Proc),
    %supervisor:delete_child(ejabberd_sup, Proc).
    ok.


do_route(Host, ServerHost, From, RoomRef, Function, Args) ->
    ?DEBUG(?MODULE_STRING " do_route: From: ~p Ref: ~p Function: ~p Args: ~p", [ From, RoomRef, Function, Args ]),
    case mnesia:dirty_read(muc_online_room, {RoomRef, Host}) of
        [] ->
            ?ERROR_MSG(?MODULE_STRING " Room ~p (~p) is not available, starting it", [ RoomRef, Host ]),
            RoomType = 0,
            gen_server:cast(self(), {create, RoomType, From, RoomRef, {Function, Args}}),
            ok;

        [R] ->
            Pid = R#muc_online_room.pid,
            %?DEBUG(?MODULE_STRING " do_route: send to process ~p: call: muc_room:~p [ ~p | ~p] \n", [Pid, Function, Pid, Args]),
            %apply(muc_room, Function, [Pid | Args]),
            ?DEBUG(?MODULE_STRING " do_route: send to process ~p: call: hyp_live:~p( ~p, ~p)\n", [Pid, Function, Pid, Args]),
            hyp_live:Function(Pid, Args),
            ok
    end.

get_rooms(ServerHost, Host) ->
    LServer = jlib:nameprep(ServerHost),
    get_rooms(LServer, Host,
              gen_mod:db_type(LServer, ?MODULE)).

get_rooms(_LServer, Host, _mnesia) ->
    case catch mnesia:dirty_select(muc_room,
        [{#muc_room{
            name_host = {'_', Host}, 
            _ = '_'},
            [], ['$_']}])
    of
        {'EXIT', Reason} -> 
            ?ERROR_MSG("~p", [Reason]), [];
        Rs -> 
            Rs
    end.

start_new_room(Host, ServerHost, Access, Room,
        HistorySize, RoomShaper, From,
        Nick, DefRoomOpts) ->
    case restore_room(ServerHost, Room, Host) of
        error ->
            ?DEBUG("Game: open new room '~s'~n", [Room]),
            mod_muc_room:start(Host, ServerHost, Access,
                    Room, HistorySize,
                    RoomShaper, From,
                    Nick, DefRoomOpts);
        Opts ->
            ?DEBUG("Game: restore room '~s'~n", [Room]),
            mod_muc_room:start(Host, ServerHost, Access,
                    Room, HistorySize,
                    RoomShaper, Opts)
    end.

register_room(Host, Room, Pid) ->
    ?DEBUG(?MODULE_STRING ".~p Registering room: ~p@~p, pid: ~p", [ ?LINE, Room, Host, Pid ]),
    F = fun() ->
        mnesia:write(#muc_online_room{
            name_host = {Room, Host},
            pid = Pid})
    end,
    case catch mnesia:activity({transaction, 2}, F) of
        {'EXIT', _Reason} ->
            false;
        {ok, Pid} = Result ->
            Result;
        _ ->
            false
    end.

existing_room(Host, Room) ->
    ?DEBUG(?MODULE_STRING " is room: ~p existing ?", [ {Room, Host} ]),
    F = fun() ->
        case mnesia:read(muc_online_room, {Room, Host}) of
            [] ->
                false;
            [#muc_online_room{pid=Pid}] ->
                {ok, Pid}
        end
    end,
    case catch mnesia:activity({transaction, 2}, F) of
        {'EXIT', _Reason} ->
            false;
        {ok, Pid} = Result ->
            Result;
        _ ->
            false
    end.

iq_disco_info(Lang) ->
    [#xmlel{name = <<"identity">>,
	    attrs =
		[{<<"category">>, <<"conference">>},
		 {<<"type">>, <<"text">>},
		 {<<"name">>,
		  translate:translate(Lang, <<"Chatrooms">>)}],
	    children = []},
     #xmlel{name = <<"feature">>,
	    attrs = [{<<"var">>, ?NS_DISCO_INFO}], children = []},
     #xmlel{name = <<"feature">>,
	    attrs = [{<<"var">>, ?NS_DISCO_ITEMS}], children = []},
     #xmlel{name = <<"feature">>,
	    attrs = [{<<"var">>, ?NS_MUC}], children = []},
     #xmlel{name = <<"feature">>,
	    attrs = [{<<"var">>, ?NS_MUC_UNIQUE}], children = []},
     #xmlel{name = <<"feature">>,
	    attrs = [{<<"var">>, ?NS_REGISTER}], children = []},
     #xmlel{name = <<"feature">>,
	    attrs = [{<<"var">>, ?NS_RSM}], children = []},
     #xmlel{name = <<"feature">>,
	    attrs = [{<<"var">>, ?NS_VCARD}], children = []}].

iq_disco_items(Host, From, Lang, none) ->
    lists:zf(fun (#muc_online_room{name_host =
				       {Name, _Host},
				   pid = Pid}) ->
		     case catch gen_fsm:sync_send_all_state_event(Pid,
								  {get_disco_item,
								   From, Lang},
								  100)
			 of
		       {item, Desc} ->
			   flush(),
			   {true,
			    #xmlel{name = <<"item">>,
				   attrs =
				       [{<<"jid">>,
					 jlib:jid_to_string({Name, Host,
							     <<"">>})},
					{<<"name">>, Desc}],
				   children = []}};
		       _ -> false
		     end
	     end, get_vh_rooms(Host));

iq_disco_items(Host, From, Lang, Rsm) ->
    {Rooms, RsmO} = get_vh_rooms(Host, Rsm),
    RsmOut = jlib:rsm_encode(RsmO),
    lists:zf(fun (#muc_online_room{name_host =
				       {Name, _Host},
				   pid = Pid}) ->
		     case catch gen_fsm:sync_send_all_state_event(Pid,
								  {get_disco_item,
								   From, Lang},
								  100)
			 of
		       {item, Desc} ->
			   flush(),
			   {true,
			    #xmlel{name = <<"item">>,
				   attrs =
				       [{<<"jid">>,
					 jlib:jid_to_string({Name, Host,
							     <<"">>})},
					{<<"name">>, Desc}],
				   children = []}};
		       _ -> false
		     end
	     end,
	     Rooms)
      ++ RsmOut.

get_vh_rooms(Host, #rsm_in{max=M, direction=Direction, id=I, index=Index})->
    AllRooms = lists:sort(get_vh_rooms(Host)),
    Count = erlang:length(AllRooms),
    Guard = case Direction of
		_ when Index =/= undefined -> [{'==', {element, 2, '$1'}, Host}];
		aft -> [{'==', {element, 2, '$1'}, Host}, {'>=',{element, 1, '$1'} ,I}];
		before when I =/= []-> [{'==', {element, 2, '$1'}, Host}, {'=<',{element, 1, '$1'} ,I}];
		_ -> [{'==', {element, 2, '$1'}, Host}]
	    end,
    L = lists:sort(
	  mnesia:dirty_select(muc_online_room,
			      [{#muc_online_room{name_host = '$1', _ = '_'},
				Guard,
				['$_']}])),
    L2 = if
	     Index == undefined andalso Direction == before ->
		 lists:reverse(lists:sublist(lists:reverse(L), 1, M));
	     Index == undefined ->
		 lists:sublist(L, 1, M);
	     Index > Count  orelse Index < 0 ->
		 [];
	     true ->
		 lists:sublist(L, Index+1, M)
	 end,
    if L2 == [] -> {L2, #rsm_out{count = Count}};
       true ->
	   H = hd(L2),
	   NewIndex = get_room_pos(H, AllRooms),
	   T = lists:last(L2),
	   {F, _} = H#muc_online_room.name_host,
	   {Last, _} = T#muc_online_room.name_host,
	   {L2,
	    #rsm_out{first = F, last = Last, count = Count,
		     index = NewIndex}}
    end.

%% @doc Return the position of desired room in the list of rooms.
%% The room must exist in the list. The count starts in 0.
%% @spec (Desired::muc_online_room(), Rooms::[muc_online_room()]) -> integer()
get_room_pos(Desired, Rooms) ->
    get_room_pos(Desired, Rooms, 0).

get_room_pos(Desired, [HeadRoom | _], HeadPosition)
    when Desired#muc_online_room.name_host ==
	   HeadRoom#muc_online_room.name_host ->
    HeadPosition;
get_room_pos(Desired, [_ | Rooms], HeadPosition) ->
    get_room_pos(Desired, Rooms, HeadPosition + 1).

flush() -> receive _ -> flush() after 0 -> ok end.

-define(XFIELD(Type, Label, Var, Val),
%% @doc Get a pseudo unique Room Name. The Room Name is generated as a hash of 
%%      the requester JID, the local time and a random salt.
%%
%%      "pseudo" because we don't verify that there is not a room
%%       with the returned Name already created, nor mark the generated Name 
%%       as "already used".  But in practice, it is unique enough. See
%%       http://xmpp.org/extensions/xep-0045.html#createroom-unique
	#xmlel{name = <<"field">>,
	       attrs =
		   [{<<"type">>, Type},
		    {<<"label">>, translate:translate(Lang, Label)},
		    {<<"var">>, Var}],
	       children =
		   [#xmlel{name = <<"value">>, attrs = [],
			   children = [{xmlcdata, Val}]}]}).

iq_get_unique(From) ->
    {xmlcdata,
     p1_sha:sha(term_to_binary([From, now(),
			     randoms:get_string()]))}.

get_nick(ServerHost, Host, From) ->
    LServer = jlib:nameprep(ServerHost),
    get_nick(LServer, Host, From,
	     gen_mod:db_type(LServer, ?MODULE)).

get_nick(_LServer, Host, From, mnesia) ->
    {LUser, LServer, _} = jlib:jid_tolower(From),
    LUS = {LUser, LServer},
    case catch mnesia:dirty_read(muc_registered,
				 {LUS, Host})
	of
      {'EXIT', _Reason} -> error;
      [] -> error;
      [#muc_registered{nick = Nick}] -> Nick
    end;
get_nick(LServer, Host, From, odbc) ->
    SJID =
	ejabberd_odbc:escape(jlib:jid_to_string(jlib:jid_tolower(jlib:jid_remove_resource(From)))),
    SHost = ejabberd_odbc:escape(Host),
    case catch ejabberd_odbc:sql_query(LServer,
				       [<<"select nick from muc_registered where "
					  "jid='">>,
					SJID, <<"' and host='">>, SHost,
					<<"';">>])
	of
      {selected, [<<"nick">>], [[Nick]]} -> Nick;
      _ -> error
    end.

iq_get_register_info(ServerHost, Host, From, Lang) ->
    {Nick, Registered} = case get_nick(ServerHost, Host,
				       From)
			     of
			   error -> {<<"">>, []};
			   N ->
			       {N,
				[#xmlel{name = <<"registered">>, attrs = [],
					children = []}]}
			 end,
    Registered ++
      [#xmlel{name = <<"instructions">>, attrs = [],
	      children =
		  [{xmlcdata,
		    translate:translate(Lang,
					<<"You need a client that supports x:data "
					  "to register the nickname">>)}]},
       #xmlel{name = <<"x">>,
	      attrs = [{<<"xmlns">>, ?NS_XDATA}],
	      children =
		  [#xmlel{name = <<"title">>, attrs = [],
			  children =
			      [{xmlcdata,
				<<(translate:translate(Lang,
						       <<"Nickname Registration at ">>))/binary,
				  Host/binary>>}]},
		   #xmlel{name = <<"instructions">>, attrs = [],
			  children =
			      [{xmlcdata,
				translate:translate(Lang,
						    <<"Enter nickname you want to register">>)}]},
		   ?XFIELD(<<"text-single">>, <<"Nickname">>, <<"nick">>,
			   Nick)]}].

set_nick(ServerHost, Host, From, Nick) ->
    LServer = jlib:nameprep(ServerHost),
    set_nick(LServer, Host, From, Nick,
	     gen_mod:db_type(LServer, ?MODULE)).

set_nick(_LServer, Host, From, Nick, mnesia) ->
    {LUser, LServer, _} = jlib:jid_tolower(From),
    LUS = {LUser, LServer},
    F = fun () ->
		case Nick of
		  <<"">> ->
		      mnesia:delete({muc_registered, {LUS, Host}}), ok;
		  _ ->
		      Allow = case mnesia:select(muc_registered,
						 [{#muc_registered{us_host =
								       '$1',
								   nick = Nick,
								   _ = '_'},
						   [{'==', {element, 2, '$1'},
						     Host}],
						   ['$_']}])
				  of
				[] -> true;
				[#muc_registered{us_host = {U, _Host}}] ->
				    U == LUS
			      end,
		      if Allow ->
			     mnesia:write(#muc_registered{us_host = {LUS, Host},
							  nick = Nick}),
			     ok;
			 true -> false
		      end
		end
	end,
    mnesia:transaction(F);
set_nick(LServer, Host, From, Nick, odbc) ->
    JID =
	jlib:jid_to_string(jlib:jid_tolower(jlib:jid_remove_resource(From))),
    SJID = ejabberd_odbc:escape(JID),
    SNick = ejabberd_odbc:escape(Nick),
    SHost = ejabberd_odbc:escape(Host),
    F = fun () ->
		case Nick of
		  <<"">> ->
		      ejabberd_odbc:sql_query_t([<<"delete from muc_registered where ">>,
						 <<"jid='">>, SJID,
						 <<"' and host='">>, Host,
						 <<"';">>]),
		      ok;
		  _ ->
		      Allow = case
				ejabberd_odbc:sql_query_t([<<"select jid from muc_registered ">>,
							   <<"where nick='">>,
							   SNick,
							   <<"' and host='">>,
							   SHost, <<"';">>])
				  of
				{selected, [<<"jid">>], [[J]]} -> J == JID;
				_ -> true
			      end,
		      if Allow ->
			     odbc_queries:update_t(<<"muc_registered">>,
						   [<<"jid">>, <<"host">>,
						    <<"nick">>],
						   [SJID, SHost, SNick],
						   [<<"jid='">>, SJID,
						    <<"' and host='">>, SHost,
						    <<"'">>]),
			     ok;
			 true -> false
		      end
		end
	end,
    ejabberd_odbc:sql_transaction(LServer, F).

iq_set_register_info(ServerHost, Host, From, Nick,
		     Lang) ->
    case set_nick(ServerHost, Host, From, Nick) of
      {atomic, ok} -> {result, []};
      {atomic, false} ->
	  ErrText = <<"That nickname is registered by another "
		      "person">>,
	  {error, ?ERRT_CONFLICT(Lang, ErrText)};
      _ -> {error, ?ERR_INTERNAL_SERVER_ERROR}
    end.

process_iq_register_set(ServerHost, Host, From, SubEl,
			Lang) ->
    #xmlel{children = Els} = SubEl,
    case xml:get_subtag(SubEl, <<"remove">>) of
      false ->
	  case xml:remove_cdata(Els) of
	    [#xmlel{name = <<"x">>} = XEl] ->
		case {xml:get_tag_attr_s(<<"xmlns">>, XEl),
		      xml:get_tag_attr_s(<<"type">>, XEl)}
		    of
		  {?NS_XDATA, <<"cancel">>} -> {result, []};
		  {?NS_XDATA, <<"submit">>} ->
		      XData = jlib:parse_xdata_submit(XEl),
		      case XData of
			invalid -> {error, ?ERR_BAD_REQUEST};
			_ ->
			    case lists:keysearch(<<"nick">>, 1, XData) of
			      {value, {_, [Nick]}} when Nick /= <<"">> ->
				  iq_set_register_info(ServerHost, Host, From,
						       Nick, Lang);
			      _ ->
				  ErrText =
				      <<"You must fill in field \"Nickname\" "
					"in the form">>,
				  {error, ?ERRT_NOT_ACCEPTABLE(Lang, ErrText)}
			    end
		      end;
		  _ -> {error, ?ERR_BAD_REQUEST}
		end;
	    _ -> {error, ?ERR_BAD_REQUEST}
	  end;
      _ ->
	  iq_set_register_info(ServerHost, Host, From, <<"">>,
			       Lang)
    end.

iq_get_vcard(Lang) ->
    [#xmlel{name = <<"FN">>, attrs = [],
	    children = [{xmlcdata, <<"messaging/game">>}]},
     #xmlel{name = <<"URL">>, attrs = [],
	    children = [{xmlcdata, ?EJABBERD_URI}]},
     #xmlel{name = <<"DESC">>, attrs = [],
	    children =
		[{xmlcdata,
		  <<(translate:translate(Lang,
					 <<"Game Component">>))/binary,
		    "\nCopyright (c) 2013-2014 harmony">>}]}].


broadcast_service_message(Host, Msg) ->
    lists:foreach( fun(#muc_online_room{pid = Pid}) ->
        gen_fsm:send_all_state_event(
            Pid, {service_message, Msg})
        end, get_vh_rooms(Host)).


get_vh_rooms(Host) ->
    mnesia:dirty_select(muc_online_room,
            [{#muc_online_room{name_host = '$1', _ = '_'},
            [{'==', {element, 2, '$1'}, Host}],
            ['$_']}]).


clean_table_from_bad_node(Node) ->
    F = fun() ->
    Es = mnesia:select(
            muc_online_room,
            [{#muc_online_room{pid = '$1', _ = '_'},
            [{'==', {node, '$1'}, Node}],
            ['$_']}]),
    lists:foreach(fun(E) ->
            mnesia:delete_object(E)
            end, Es)
    end,
    mnesia:async_dirty(F).

clean_table_from_bad_node(Node, Host) ->
    F = fun() ->
    Es = mnesia:select(
            muc_online_room,
            [{#muc_online_room{pid = '$1',
            name_host = {'_', Host},
            _ = '_'},
            [{'==', {node, '$1'}, Node}],
            ['$_']}]),
    lists:foreach(fun(E) ->
            mnesia:delete_object(E)
            end, Es)
        end,
    mnesia:async_dirty(F).

opts_to_binary(Opts) ->
    lists:map(
      fun({title, Title}) ->
              {title, iolist_to_binary(Title)};
         ({description, Desc}) ->
              {description, iolist_to_binary(Desc)};
         ({password, Pass}) ->
              {password, iolist_to_binary(Pass)};
         ({subject, Subj}) ->
              {subject, iolist_to_binary(Subj)};
         ({subject_author, Author}) ->
              {subject_author, iolist_to_binary(Author)};
         ({affiliations, Affs}) ->
              {affiliations, lists:map(
                               fun({{U, S, R}, Aff}) ->
                                       NewAff =
                                           case Aff of
                                               {A, Reason} ->
                                                   {A, iolist_to_binary(Reason)};
                                               _ ->
                                                   Aff
                                           end,
                                       {{iolist_to_binary(U),
                                         iolist_to_binary(S),
                                         iolist_to_binary(R)},
                                        NewAff}
                               end, Affs)};
         ({captcha_whitelist, CWList}) ->
              {captcha_whitelist, lists:map(
                                    fun({U, S, R}) ->
                                            {iolist_to_binary(U),
                                             iolist_to_binary(S),
                                             iolist_to_binary(R)}
                                    end, CWList)};
         (Opt) ->
              Opt
      end, Opts).

update_tables(Host) ->
    update_muc_room_table(Host),
    update_muc_registered_table(Host).

update_muc_room_table(_Host) ->
    Fields = record_info(fields, muc_room),
    case mnesia:table_info(muc_room, attributes) of
      Fields ->
          ejabberd_config:convert_table_to_binary(
            muc_room, Fields, set,
            fun(#muc_room{name_host = {N, _}}) -> N end,
            fun(#muc_room{name_host = {N, H},
                          opts = Opts} = R) ->
                    R#muc_room{name_host = {iolist_to_binary(N),
                                            iolist_to_binary(H)},
                               opts = opts_to_binary(Opts)}
            end);
      _ ->
          ?INFO_MSG("Recreating muc_room table", []),
          mnesia:transform_table(muc_room, ignore, Fields)
    end.

update_muc_registered_table(_Host) ->
    Fields = record_info(fields, muc_registered),
    case mnesia:table_info(muc_registered, attributes) of
      Fields ->
          ejabberd_config:convert_table_to_binary(
            muc_registered, Fields, set,
            fun(#muc_registered{us_host = {_, H}}) -> H end,
            fun(#muc_registered{us_host = {{U, S}, H},
                                nick = Nick} = R) ->
                    R#muc_registered{us_host = {{iolist_to_binary(U),
                                                 iolist_to_binary(S)},
                                                iolist_to_binary(H)},
                                     nick = iolist_to_binary(Nick)}
            end);
      _ ->
	  ?INFO_MSG("Recreating muc_registered table", []),
	  mnesia:transform_table(muc_registered, ignore, Fields)
    end.

export(_Server) ->
    [{muc_room,
      fun(Host, #muc_room{name_host = {Name, RoomHost}, opts = Opts}) ->
              case str:suffix(Host, RoomHost) of
                  true ->
                      SName = ejabberd_odbc:escape(Name),
                      SRoomHost = ejabberd_odbc:escape(RoomHost),
                      SOpts = ejabberd_odbc:encode_term(Opts),
                      [[<<"delete from muc_room where name='">>, SName,
                        <<"' and host='">>, SRoomHost, <<"';">>],
                       [<<"insert into muc_room(name, host, opts) ",
                          "values (">>,
                        <<"'">>, SName, <<"', '">>, SRoomHost,
                        <<"', '">>, SOpts, <<"');">>]];
                  false ->
                      []
              end
      end},
     {muc_registered,
      fun(Host, #muc_registered{us_host = {{U, S}, RoomHost},
                                nick = Nick}) ->
              case str:suffix(Host, RoomHost) of
                  true ->
                      SJID = ejabberd_odbc:escape(
                               jlib:jid_to_string(
                                 jlib:make_jid(U, S, <<"">>))),
                      SNick = ejabberd_odbc:escape(Nick),
                      SRoomHost = ejabberd_odbc:escape(RoomHost),
                      [[<<"delete from muc_registered where jid='">>,
                        SJID, <<"' and host='">>, SRoomHost, <<"';">>],
                       [<<"insert into muc_registered(jid, host, "
                          "nick) values ('">>,
                        SJID, <<"', '">>, SRoomHost, <<"', '">>, SNick,
                        <<"');">>]];
                  false ->
                      []
              end
      end}].

import(_LServer) ->
    [{<<"select name, host, opts from muc_room;">>,
      fun([Name, RoomHost, SOpts]) ->
              Opts = opts_to_binary(ejabberd_odbc:decode_term(SOpts)),
              #muc_room{name_host = {Name, RoomHost},
                        opts = Opts}
      end},
     {<<"select jid, host, nick from muc_registered;">>,
      fun([J, RoomHost, Nick]) ->
              #jid{user = U, server = S} =
                  jlib:string_to_jid(J),
              #muc_registered{us_host = {{U, S}, RoomHost},
                              nick = Nick}
      end}].

import(_LServer, mnesia, #muc_room{} = R) ->
    mnesia:dirty_write(R);
import(_LServer, mnesia, #muc_registered{} = R) ->
    mnesia:dirty_write(R);
import(_, _, _) ->
    pass.

string_to_jid(Data) ->
    Pattern = ets:lookup_element(jlib, string_to_jid_pattern, 2),
    case binary:split(Data, Pattern) of
        [ First, Rest ] ->
            case binary:split(Rest, Pattern) of
                [ Server, Resource ] ->
                    #jid{
                        user=First, server=Server, resource=Resource,
                        luser=First, lserver=Server, lresource=Resource };
                [ Server ] ->
                    Empty = <<>>,
                    #jid{
                        user=First, server=Server, resource=Empty,
                        luser=First, lserver=Server, lresource=Empty }
            end;
        _ ->
            {error, einval}
    end.
                

test() ->
    Opts = [],
    GameName = <<"abcd">>,
    Host = <<"messaging.harmony">>,
    create_room(Host, 1, undefined, GameName, Opts), 
    %[{muc_online_room,{<<"abcd">>,
    %                   <<"conference.messaging.harmony">>}, GamePid}] = mnesia:dirty_read(muc_online_room, {<<"abcd">>,<<"conference.messaging.harmony">>}),
    User1 = <<"user1@h">>,
    User2 = <<"user3@h2">>,
    % Add two players
    Me = self(),
    route(Host, GameName, Me, add, [ User1 ]),
    route(Host, GameName, Me, add, [ User2 ]),
    %game_master:add(GamePid, User1),
    %game_master:add(GamePid, User2),
    %game_master:game(GamePid),
    route(Host, GameName, Me, game, []),
    route(Host, GameName, Me, next, []),

    route(Host, GameName, Me, publish, []),
    %io:format("Next: ~p\n", [ game_master:next(GamePid) ]),
    route(Host, GameName, Me, answer, [User1, <<"5">>]),
    route(Host, GameName, Me, answer, [User2, <<"4">>]),
    %game_master:answer(GamePid, User1, <<"5">>),
    %game_master:answer(GamePid, User2, <<"4">>),
    %io:format("Next: ~p\n", [ game_master:next(GamePid) ]),
    route(Host, GameName, Me, next, []),
    route(Host, GameName, Me, publish, []),

    route(Host, GameName, Me, score, []),
    route(Host, GameName, Me, stop, []),
    %game_master:answer(GamePid, User1, <<"4">>),
    %game_master:answer(GamePid, User2, <<"5">>),
    %io:format("Score: ~p\n", [ game_master:score(GamePid) ]),
    %game_master:stop(GamePid).
    ok.
