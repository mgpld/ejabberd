-module(ber_protocol).
% Created ber_protocol.erl the 17:03:47 (08/04/2017) on core
% Last Modification of ber_protocol.erl at 01:58:28 (10/04/2017) on core
% 
% Author: "ak" <ak@harmonygroup.net>

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

-define(TIMEOUT, 60000).

start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.

init(Ref, Socket, Transport, _Opts = []) ->
    ok = ranch:accept_ack(Ref),
    Connection = {Transport, self(), Socket},
    Opts = [],
    {ok, Pid} = ejabberd_c2s_json:start_link({?MODULE, Connection}, Opts),
    Transport:setopts(Socket, [{packet, 2}]),
    ?DEBUG(" session started: ~p Client pid : ~p", [ Transport, Pid]),
    loop(Socket, Transport, ?TIMEOUT, #state{ pid = Pid, timeout = ?TIMEOUT }).

loop(Socket, Transport, Timeout, #state{} = State) ->
    receive
        Message ->
            ?DEBUG(?MODULE_STRING "[~5w] message: ~p\n", [ ?LINE, Message ])
    after 0 ->
        ok
    end,
    case Transport:recv(Socket, 0, Timeout) of
        {ok, <<Size:16,Data:Size/binary,_/binary>>} ->
            ?DEBUG(?MODULE_STRING "[~5w] Data 2: ~p\n", [ ?LINE, Data ]),
            case catch binary_to_term(Data) of
                {'EXIT', {badarg, Reason}} ->
                    ?ERROR_MSG("invalid Data: Reason ~p\n", [ Reason ]),
                    loop(Socket, Transport, Timeout, State);

                Decoded ->
                    ?DEBUG("Decoded Data: ~p\n", [ Decoded ]),
                    handle_data( Decoded, State ),
                    loop(Socket, Transport, Timeout, State)

            end;

        {ok, Data} ->
            ?DEBUG(?MODULE_STRING "[~5w] Data 3: ~p\n", [ ?LINE, Data ]),
            case catch binary_to_term(Data) of
                {'EXIT', {badarg, Reason}} ->
                    ?ERROR_MSG("invalid Data: Reason ~p\n", [ Reason ]),
                    loop(Socket, Transport, Timeout, State);

                Decoded ->
                    ?DEBUG("Decoded Data: ~p\n", [ Decoded ]),
                    handle_data( Decoded, State ),
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
            ?DEBUG("New event for client: ~p\n~p", [ Client, Event ]),
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
    Binary = term_to_binary(Data, [{compressed, 9}]),
    Transport:send(Socket, Binary).

close({Transport, _Pid, Socket}) ->
    Transport:close(Socket).

parse(Term) ->
    to_event(Term).

%% JSON PACKET are identified by their type and by a specific Id
%% This id is meant to be resent in the response (if any) to be handled
%% by the javascript client side to execute a callback if any...
to_event({Type, Args, Id}) ->
    to_event(Id, Type, Args);

to_event({struct, Args}) ->
    {undefined, Args};

to_event(_) ->
        [].

to_event(Id, <<"p">>, Args) ->
    presence(Id, Args);

to_event(Id, <<"m">>, Args) ->
    message(Id, Args);

to_event(Id, <<"l">>, Args) ->
    login(Id, Args);

to_event(Id, <<"a">>, Args) ->
    action(Id, Args);

%to_event(Id, <<"a">>, Action) ->
%    action(Id, Action);

to_event(Id, <<"i">>, Args) ->
    invite(Id, Args);

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

