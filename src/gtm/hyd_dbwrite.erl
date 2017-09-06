-module(hyd_dbwrite).
% Created hyd_dbwrite.erl the 12:25:51 (26/01/2016) on core
%% Last Modification of hyd_dbwrite.erl at 00:12:08 (06/09/2017) on core
% 
% Author: "rolph" <ak@harmonygroup.net>

%% API
-export([
    tcp_init/2,
    udp_init/2, 
    udp_recv/5, 
    start/2, 
    socket_type/0
]).

-include("ejabberd.hrl").
-include("logger.hrl").

-define(GTM_MODULE, <<"external">>).
-define(GTM_METHOD, <<"run">>).

%%%===================================================================
%%% API
%%%===================================================================
tcp_init(_Socket, _Opts) ->
    ok.

udp_init(_Socket, _Opts) ->
    ok.

udp_recv(Socket, Addr, Port, Packet, Opts) ->
    spawn(fun() ->
            handle_packet(Socket, Addr, Port, Packet, Opts)
    end).

start(_Opaque, _Opts) ->
    ok.

socket_type() ->
    raw.

%%%===================================================================
%%% Internal functions
%%%===================================================================
handle_packet(_Socket, _Addr, Port, Packet, Opts) ->
    ?DEBUG(?MODULE_STRING ".(~p) Packet: ~p, Opts: ~p", [ ?LINE, Packet, Opts ]),
    [ Head | Args ] = binary:split(Packet, <<" ">>),
    [ <<>>, Domain, Method | _ ] = binary:split(Head,<<"/">>, [global,trim]),
    TransId = Port,
    db(TransId, Domain, Method, Args),
    receive
        {db, TransId, {ok, Success}} ->
            ?DEBUG(?MODULE_STRING ".~p Domain: ~p Method: ~p, Args: ~p: ~p", [ ?LINE, Domain, Method, Args, Success ]),
            ok;

        {db, TransId, {error, Error}} ->
            ?ERROR_MSG(?MODULE_STRING ".~p FAIL! Domain: ~p Method: ~p, Args: ~p: ~p", [ ?LINE, Domain, Method, Args, Error ]),
            ok;
    
        _Result ->
            ?ERROR_MSG(?MODULE_STRING ".~p FAIL! Domain: ~p Method: ~p, Args: ~p: ~p", [ ?LINE, Domain, Method, Args, _Result ]),
            ok
            
    after 10000 ->
            ?DEBUG(?MODULE_STRING ".~p FAIL! Timeout: Domain: ~p Method: ~p, Args: ~p", [ ?LINE, Domain, Method, Args ]),
            ok
    end.
    

db(TransId, Domain, Method, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    db:cast(TransId, ?GTM_METHOD, ?GTM_MODULE, [ Method, Domain | FilteredArgs]).


