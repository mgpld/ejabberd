-module(gtmproxy_app).
% Created gtmproxy_app.erl the 00:00:00 (16/06/2014) on core
% Last Modification of gtmproxy_app.erl at 06:59:37 (03/02/2015) on core
% 
% Author: "rolph" <rolphin@free.fr>

-define( SERVER, ?MODULE ).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    case init:get_argument(gtmproxy) of
        error ->
            error_logger:error_msg(?MODULE_STRING " Missing -gtmproxy Childs Prefix StartPortRange\n", []),
            start_error;

        {ok, [[Childs, Prefix, Port]]} ->
            Queue = gtmproxy, 
            gtmproxy_sup:start_link(
                list_to_integer(Childs), Prefix, Queue, list_to_integer(Port))
    end.

stop(_State) ->
    ok.

