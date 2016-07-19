-module(gtmworker_sup).
% Created gtmworker_sup.erl the 04:07:10 (04/07/2014) on core
% Last Modification of gtmworker_sup.erl at 08:14:55 (10/07/2014) on core
% 
% Author: "rolph" <rolphin@free.fr>

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init(_Args) ->
    {ok, {{one_for_one, 5, 10}, []}}.
