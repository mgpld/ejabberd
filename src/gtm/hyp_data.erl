-module(hyp_data).
% Created hyp_data.erl the 18:00:15 (27/05/2015) on core
% Last Modification of hyp_data.erl at 12:16:57 (06/04/2017) on core
% 
% Author: "rolph" <rolphin@free.fr>

-export([
    action/4,
    execute/3,
    extract/2
]).

-include("ejabberd.hrl").
-include("logger.hrl").

action(Userid, Fqid, Action, Args) ->
    ?DEBUG(?MODULE_STRING " action: Userid ~p, Action ~p, Args: ~p\n", [ Userid, Action, Args ]),
    execute( hyd_fqids, action, [ Fqid, Action, [ Userid | Args ] ]).

execute( Module, Function, Args) ->
    ?DEBUG(?MODULE_STRING "[~5w] execute: Module ~p, Function ~p, Args: ~p\n", [ ?LINE, Module, Function, Args ]),
    Result = apply(Module, Function, Args), % synchro call
    ?DEBUG(?MODULE_STRING "[~5w] execute: Result: ~p\n", [ ?LINE, Result ]),
    case Result of 
        [<<>>] ->
            {error, invalid};

        {error, _ } = Error ->
            ?DEBUG(?MODULE_STRING " execute: error: ~p", [ Error ]),
            Error;

        [ {error, _} = Error | _ ] -> % backend app error
            ?DEBUG(?MODULE_STRING " execute db: error: ~p", [ Error ]),
            Error;

        [] ->
            {ok, []}; % empty response because nothing was found or done

        [ Response ] -> % there is only one response
            {ok, Response};

        Response ->  % there is many response or a complex response
            {ok, Response}

    end.

-spec extract( 
    Path :: list(),
    Props :: list({binary(), binary()})) -> binary() | <<>>.

extract(Path, Props) ->
    do_get(Path, Props, <<>>).

-spec do_get( 
    Path :: list(),
    Props :: list({binary(), binary()}),
    Default :: term() ) -> binary() | term().


do_get([], Value, _) ->
    Value;
do_get([Key | Rest], [Key | _], Default) ->
    do_get(Rest, true, Default);
do_get([Key | Rest], [{Key, Value} | _], Default) ->
    do_get(Rest, Value, Default);
do_get(Path, [_ | Left], Default) ->
    do_get(Path, Left, Default);
do_get(_, _, Default) ->
    Default.


