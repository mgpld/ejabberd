-module(json_protocol).
% Created json_protocol.erl the 22:01:35 (14/05/2016) on core
% Last Modification of json_protocol.erl at 16:04:48 (20/09/2016) on core
% 
% Author: "ak" <ak@harmonygroup.net>
%% Feel free to use, reuse and abuse the code in this file.

-export([
    start_link/4, 
    init/4]).

-export([
    send/2,
    close/1,
    setopts/2,
    monitor/1,
    peername/1,
    sockname/1
]).

-include("logger.hrl").

-record(state, {
    pid,
    timeout 
}).

-define(TIMEOUT, 10000).

start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.

init(Ref, Socket, Transport, _Opts = []) ->
    ok = ranch:accept_ack(Ref),
    Connection = {Transport, self(), Socket},
    Opts = [],
    {ok, Pid} = ejabberd_c2s_json:start_link({?MODULE, Connection}, Opts),
    ?DEBUG(?MODULE_STRING "[~5w] session started: Client pid : ~p", [ ?LINE, Pid]),
    loop(Socket, Transport, ?TIMEOUT, #state{ pid = Pid, timeout = 5000 }).

loop(Socket, Transport, Timeout, #state{} = State) ->
    receive
        Message ->
            ?DEBUG(?MODULE_STRING ".~p message: ~p\n", [ ?LINE, Message ])
    after 0 ->
        ok
    end,
    case Transport:recv(Socket, 0, Timeout) of
        {ok, Data} ->
            ?DEBUG(?MODULE_STRING "[~5w] Data: ~p\n", [ ?LINE, Data ]),
            case sockjs_json:decode(Data) of
                {ok, Decoded} ->
                    handle_data( Decoded, State ),
                    loop(Socket, Transport, Timeout, State);

                _ ->
                    ?DEBUG(?MODULE_STRING "[~5w] invalid Data: ~p\n", [ ?LINE, Data ]),
                    loop(Socket, Transport, Timeout, State)
            end;

        _ ->
            {error, einval}
    end.

handle_data( Data, #state{ pid = Client } = _State) ->
    case parse(Data) of
        [] ->
            ok;

        Event ->
            %?DEBUG(?MODULE_STRING ".~p Sending: ~p to ~p", [ ?LINE, Event, Client ]),
            catch gen_fsm:send_event(Client, Event)
    end.
    
peername({ Transport, _Pid, Socket }) ->
    Transport:peername(Socket).

sockname({ Transport, _Pid, Socket }) ->
    Transport:sockname(Socket).

setopts(_Sock, _Opts) ->
	ok.

monitor({_Module, Pid, _Socket}) ->
	erlang:monitor(process, Pid).

send({Transport, _Pid, Socket}, Data) ->
    Json = sockjs_json:encode(Data),
    Transport:send(Socket, [Json, $\n]).

close({Transport, _Pid, Socket}) ->
    Transport:close(Socket).

parse(Json) ->
    to_event(Json).

%% JSON PACKET are identified by their type and by a specific Id
%% This id is meant to be resent in the response (if any) to be handled
%% by the javascript client side to execute a callback if any...
to_event({struct, [{Type, Args}, {<<"id">>, Id}]}) ->
    to_event(Id, Type, Args);

to_event({struct, Args}) ->
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

%Json: {message,[{<<"action">>,{struct,[{<<"type">>,<<"new-discussion">>}]}},
%                {<<"id">>,13}]} to <0.1428.0>


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

