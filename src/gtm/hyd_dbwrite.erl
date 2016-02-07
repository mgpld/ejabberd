-module(hyd_dbwrite).
% Created hyd_dbwrite.erl the 12:25:51 (26/01/2016) on core
% Last Modification of hyd_dbwrite.erl at 14:08:07 (26/01/2016) on core
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
    %ejabberd:start_app(p1_stun),
    %stun:tcp_init(Socket, prepare_turn_opts(Opts)).

udp_init(_Socket, _Opts) ->
    ok.
    %ejabberd:start_app(p1_stun),
    %stun:udp_init(Socket, prepare_turn_opts(Opts)).

udp_recv(Socket, Addr, Port, Packet, Opts) ->
    spawn(fun() ->
            handle_packet(Socket, Addr, Port, Packet, Opts)
    end).

start(Opaque, Opts) ->
    ok.

socket_type() ->
    raw.

%%%===================================================================
%%% Internal functions
%%%===================================================================
prepare_turn_opts(Opts) ->
    UseTurn = proplists:get_bool(use_turn, Opts),
    prepare_turn_opts(Opts, UseTurn).

prepare_turn_opts(Opts, _UseTurn = false) ->
    Opts;
prepare_turn_opts(Opts, _UseTurn = true) ->
    NumberOfMyHosts = length(?MYHOSTS),
    case proplists:get_value(turn_ip, Opts) of
	undefined ->
	    ?WARNING_MSG("option 'turn_ip' is undefined, "
			 "more likely the TURN relay won't be working "
			 "properly", []);
	_ ->
	    ok
    end,
    AuthFun = fun ejabberd_auth:get_password_s/2,
    Shaper = gen_mod:get_opt(shaper, Opts,
			     fun(S) when is_atom(S) -> S end,
			     none),
    AuthType = gen_mod:get_opt(auth_type, Opts,
			       fun(anonymous) -> anonymous;
				  (user) -> user
			       end, user),
    Realm = case gen_mod:get_opt(auth_realm, Opts, fun iolist_to_binary/1) of
		undefined when AuthType == user ->
		    if NumberOfMyHosts > 1 ->
			    ?WARNING_MSG("you have several virtual "
					 "hosts configured, but option "
					 "'auth_realm' is undefined and "
					 "'auth_type' is set to 'user', "
					 "more likely the TURN relay won't "
					 "be working properly. Using ~s as "
					 "a fallback", [?MYNAME]);
		       true ->
			    ok
		    end,
		    [{auth_realm, ?MYNAME}];
		_ ->
		    []
	    end,
    MaxRate = shaper:get_max_rate(Shaper),
    Realm ++ [{auth_fun, AuthFun},{shaper, MaxRate} |
	      lists:keydelete(shaper, 1, Opts)].

handle_packet(Socket, Addr, Port, Packet, Opts) ->
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
            ?DEBUG(?MODULE_STRING ".~p FAIL! Domain: ~p Method: ~p, Args: ~p: ~p", [ ?LINE, Domain, Method, Args, Error ]),
            ok;
    
        _Result ->
            ?DEBUG(?MODULE_STRING ".~p FAIL! Domain: ~p Method: ~p, Args: ~p: ~p", [ ?LINE, Domain, Method, Args, _Result ]),
            ok
            
    after 1000 ->
            ?DEBUG(?MODULE_STRING ".~p FAIL! Timeout Method: ~p, Args: ~p", [ ?LINE, Method, Args ]),
            %handle_packet(Socket, Addr, Port, Packet, Opts)
            ok
    end.
    

db(TransId, Domain, Method, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    db:cast(TransId, ?GTM_METHOD, ?GTM_MODULE, [ Method, Domain | FilteredArgs]).


