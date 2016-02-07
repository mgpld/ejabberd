%%%----------------------------------------------------------------------
%%%
%%% Copyright (c) 2012, Jan Vincent Liwanag <jvliwanag@gmail.com>
%%%
%%% This file is part of ejabberd_sockjs.
%%%
%%% ejabberd_sockjs is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% ejabberd_sockjs is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with ejabberd_sockjs.  If not, see <http://www.gnu.org/licenses/>.
%%%
%%%----------------------------------------------------------------------

-module(ejabberd_sockjs).
-author('jvliwanag@gmail.com').
-author('mgpld@free.fr').

-behavior(gen_server).

-include_lib("ejabberd.hrl").
-include_lib("logger.hrl").

%% API
-export([
	start/1,
	start_link/1,
	start_supervised/1,
	receive_bin/2
]).

%% ejabberd_socket callbacks
-export([
	controlling_process/2,
	sockname/1,
	peername/1,
	setopts/2,
	custom_receiver/1,
	monitor/1,
	become_controller/2,
	send/2,
	reset_stream/1,

	%% TODO
	change_shaper/2
]).

%% ejabberd_listener callbacks
-export([
    socket_type/0,
    start_listener/2,
    close/1
]).

%% gen_server callbacks
-export([
	init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3
]).

-record(state, {
	conn :: tuple(),
	controller :: pid() | undefined,
	xml_stream_state,
	prebuff = [],
	c2s_pid :: pid() | undefined
}).


-record(sockjs_state, {
	conn_pid :: pid() | undefined
}).

%% API

start(Conn) ->
	gen_server:start(?MODULE, [Conn], []).

start_link(Conn) ->
	gen_server:start_link(?MODULE, [Conn], []).


start_supervised(Conn) ->
    case catch supervisor:start_child(ejabberd_sockjs_sup, [Conn]) of
	    {ok, Pid} ->
		    {ok, Pid};
	    _Err ->
		    ?WARNING_MSG(?MODULE_STRING " Error starting sockjs session: ~p", [_Err]),
		    {error, not_started}
    end.

close({sockjs, Ref, _Conn}) ->
    gen_server:cast(Ref, stop).

-spec receive_bin(pid(), binary()) -> ok.
receive_bin(SrvRef, Bin) ->
    gen_server:cast(SrvRef, {receive_bin, Bin}).

%% ejabberd_socket callbacks

controlling_process({sockjs, Ref, _Conn}, Pid) ->
    gen_server:cast(Ref, {controlling_process, Pid}),
    ok.

%% TODO
-spec change_shaper(pid(), any()) -> ok.
change_shaper(_SrvRef, _Shaper) ->
	ok.

sockname({sockjs, _SrvRef, Conn}) ->
	Info = sockjs_session:info(Conn),
	Sockname = proplists:get_value(sockname, Info),
	{ok, Sockname}.

peername({sockjs, _SrvRef, Conn}) ->
	Info = sockjs_session:info(Conn),
	Sockname = proplists:get_value(peername, Info),
	{ok, Sockname}.

setopts(_Sock, _Opts) ->
	%% TODO implement {active, once}
	ok.

custom_receiver({sockjs, SrvRef, _Conn}) ->
	{receiver, ?MODULE, SrvRef}.

monitor({sockjs, SrvRef, _Conn}) ->
	erlang:monitor(process, SrvRef).

-spec become_controller(pid(), C2SPid :: pid()) -> ok.
become_controller(SrvRef, C2SPid) ->
	gen_server:cast(SrvRef, {become_controller, C2SPid}).

send({sockjs, SrvRef, _Conn}, Out) ->
	gen_server:cast(SrvRef, {send, Out}).

reset_stream({sockjs, SrvRef, _Conn}) ->
	gen_server:cast(SrvRef, reset_stream).

%% ejabberd_listener callbacks
-spec socket_type() -> independent.
socket_type() ->
	independent.

-type listener_opt() :: ok.
-type ip_port_tcp() :: {inet:port_number(), inet:ip4_address(), tcp}.
-spec start_listener(ip_port_tcp(), [listener_opt()]) -> {ok, pid()}.
start_listener({Port, _Ip, _}, Opts) ->
    start_app(ranch),
    start_app(cowboy),
    start_app(sockjs),
    
    Path = proplists:get_value(path, Opts, "/sockjs"),
    Prefix = proplists:get_value(prefix, Opts, Path),
    PrefixBin = list_to_binary(Prefix),
    
    SockjsState = sockjs_handler:init_state(PrefixBin, fun service_ej/3, #sockjs_state{}, []),

    RtState = sockjs_handler:init_state(<<"/rt">>, fun service_ej/3, #sockjs_state{}, []),

    VhostRoutes = [
        {<<"/sockjs/[...]">>, sockjs_cowboy_handler, SockjsState},
        {<<"/rt/[...]">>, sockjs_cowboy_handler, RtState},
        {<<"/login/[...]">>, login_handler, []}],

    Routes = [{'_',  VhostRoutes}], % any vhost
    
    Dispatch = cowboy_router:compile( Routes ),
    
    cowboy:start_http({ejabberd_sockjs_http, Port}, 100,
    	[{port, Port}],
    	[{env, [{dispatch, Dispatch}]}]).

%% gen_server callbacks
init([Conn]) ->
    Socket = {sockjs, self(), Conn},
    Opts = [],
    {ok, C2SPid} = ejabberd_c2s_json:start_link({?MODULE, Socket}, Opts),
    ?DEBUG(?MODULE_STRING ".~p Sockjs session started: Client pid : ~p", [ ?LINE, C2SPid]),
    {ok, #state{conn=Conn, c2s_pid=C2SPid}}.

handle_call(_Msg, _From, State) ->
	?WARNING_MSG(?MODULE_STRING " Unknown call msg: ~p", [_Msg]),
	{reply, {error, unknown_msg}, State}.

handle_cast({controlling_process, C2SPid}, State) ->
    ?DEBUG(?MODULE_STRING " Controlling process: is ~p", [C2SPid]),
    {noreply, State#state{ c2s_pid = C2SPid}};

handle_cast({become_controller, C2SPid}, State) ->
	?DEBUG(?MODULE_STRING " Become controller for: ~p", [ C2SPid ]),
	
	NSt = State#state{prebuff = [], c2s_pid = C2SPid},
	{noreply, NSt};

handle_cast({recv, Data}, #state{ conn=C } = State) ->
    ?DEBUG(?MODULE_STRING ".~p Received from: ~p\n~s\n", [ ?LINE, C, Data]),
    case sockjs_json:decode(Data) of
        {ok, Decoded} ->
            handle_data( Decoded, State ),
            {noreply, State};

        _ ->
            {noreply, State}
    end;

handle_cast({send, Out}, #state{conn=Connection} = State) ->
    Json = sockjs_json:encode(Out),
    sockjs_session:send(Json, Connection),
    {noreply, State};

handle_cast(reset_stream, St) ->
    {noreply, St};

handle_cast(stop, #state{ conn=Conn } = State) ->
    sockjs_session:close(timeout, "timeout", Conn),
    {stop, normal, State};
    
handle_cast(_, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal

service_ej(Conn, init, State) ->
    ?DEBUG(?MODULE_STRING ".~p New Connection: ~p, (~p)", [ ?LINE, Conn, State ]),
    {ok, Pid} = ejabberd_sockjs:start_supervised(Conn),
    {ok, State#sockjs_state{conn_pid = Pid}};

service_ej(_Conn, {recv, _} = Packet, State) ->
    %?DEBUG("Conn: ~p, Data: ~p, State: ~p", [ _Conn, Data, State ]),
    Pid = State#sockjs_state.conn_pid,
    gen_server:cast(Pid, Packet),
    %receive_bin(Pid, Data),
    {ok, State};

service_ej(_Conn, closed, #sockjs_state{ conn_pid=Pid } = State) ->
    ?DEBUG(?MODULE_STRING " Conn: ~p, closed !, State: ~p", [ _Conn, State ]),
    gen_server:cast(Pid, stop),
    {ok, State}.

start_app(App) ->
    case application:start(App) of
        ok -> ok;
        {error, {already_started, _}} -> ok
    end.

parse(Json) ->
    to_event(Json).

%% JSON PACKET are identified by their type and by a specific Id
%% This id is meant to be resent in the response (if any) to be handled
%% by the javascript client side to execute a callback if any...
to_event({struct, [{Type, Args}, {<<"id">>, Id}]}) ->
    %?DEBUG("Id: ~p Args: ~p", [ Id, Args ]),
    to_event(Id, Type, Args);

to_event({struct, Args}) ->
    %?DEBUG("Args: ~p", [ Args ]),
    {undefined, Args};

to_event(_) ->
        [].

to_event(Id, <<"presence">>, {struct, Args}) ->
    presence(Id, Args);

to_event(Id, <<"presence">>, Arg) ->
    presence(Id, Arg);

to_event(Id, <<"message">>, {struct, Args}) ->
    message(Id, Args);

to_event(Id, <<"login">>, {struct, Args}) ->
    login(Id, Args);

to_event(Id, <<"action">>, {struct, Args}) ->
    action(Id, Args);

to_event(Id, <<"action">>, Action) ->
    action(Id, Action);

to_event(Id, <<"invite">>, {struct, Args}) ->
    invite(Id, Args);

% DEPRECATED
to_event(_Id, <<"authent">> = Type, {struct, Args}) ->
    {undefined, Type, Args};

to_event(_Id, Type, {struct, Args}) ->
    {undefined, Type, Args}.

% Inital connection phase, the user is sending some credentials
% new version
login(Id, Args) ->
    {login, Id, Args}.

% A message is sent to someone or to some process (i.e. rooms)
message(Id, Args) ->
    {message, Id, Args}.

% An action is sent. Calling the database or setting a specific thing
action(Id, Args) ->
    {action, Id, Args}.

% A presence is sent, meaning that the user change its status.
presence(Id, Args) ->
    {presence, Id, Args}.

% An invite is sent, about a chat room or a web conference etc.
invite(Id, Args) ->
    {invite, Id, Args}.

handle_data( Data, #state{c2s_pid=Client,conn=Conn} = _State ) ->
    case parse(Data) of
        [] ->
            ?ERROR_MSG(?MODULE_STRING " Error don't handle:\n~p", [ Data ]);

        {undefined, Type, Args} ->
            ?ERROR_MSG(?MODULE_STRING " Unhandled json message type: ~p, args: ~p", [ Type, Args ]),
            Packet = [{<<"error">>, [ 
                {<<"code">>, 999},
                {<<"type">>, <<"protocol">>}
            ]}],
            sockjs_session:send(Packet, Conn),
            ok;
	    
        Event ->
            ?DEBUG(?MODULE_STRING " Sending: ~p to ~p", [ Event, Client ]),
            catch gen_fsm:send_event(Client, Event)
    end.

