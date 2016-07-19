-module(gtm).
% Created gtm.erl the 08:48:15 (16/08/2015) on core
% Last Modification of gtm.erl at 08:50:55 (16/08/2015) on core
%
% Author: "rolph" <rolphin@free.fr>
-export([
    start/0, start/1, start/2
]).

start() ->
    start(8,11000).

start(Childs) ->
    start(Childs, 11000).

start(Childs, Port) ->

    ChildSpec = {
        gtmproxy_sup,
        {gtmproxy_sup, start_link, [ Childs, "g", gtmproxy, Port ]},
        transient,
        infinity,
        supervisor,
        [gtmproxy_sup]},
    supervisor:start_child(ejabberd_sup, ChildSpec).
