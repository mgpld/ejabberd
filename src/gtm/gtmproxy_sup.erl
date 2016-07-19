-module(gtmproxy_sup).
% Created gtmproxy_sup.erl the 02:17:02 (16/06/2014) on core
% Last Modification of gtmproxy_sup.erl at 07:04:35 (03/02/2015) on core
%
% Author: "rolph" <rolphin@free.fr>

-behaviour(supervisor).

-export([
    init/1,
    start_link/4
]).

start_link(Childs, Prefix, Queue, Port) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Childs, Prefix, Queue, Port]).

init(Opts) ->
    Gtmworker = {
        gtmworker_sup,
        {gtmworker_sup, start_link, []},
        transient,
        5000,
        worker,
        [gtmworker_sup]},
    Gtmproxy = {
        gtmproxy_srv,
        {gtmproxy_srv, start_link, Opts},
        transient,
        5000,
        worker,
        [gtmproxy_srv]},
    Valve = {
        valve_srv,
        {valve_srv, start_link, [gtmproxy]},
        transient,
        5000,
        worker,
        [valve_srv]},

    {ok, { {one_for_one, 5, 10}, [Gtmworker,Valve,Gtmproxy]} }.

