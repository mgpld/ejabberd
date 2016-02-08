-module(hyp_data).
% Created hyp_data.erl the 18:00:15 (27/05/2015) on core
% Last Modification of hyp_data.erl at 15:00:44 (08/02/2016) on sd-19230
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
    ?DEBUG(?MODULE_STRING " execute: Module ~p, Function ~p, Args: ~p\n", [ Module, Function, Args ]),
    case get_node() of
        {ok, Node} -> 
            %Result = rpc:call(Node, Module, Function, Args), % synchro call
            Result = apply(Module, Function, Args), % synchro call
            ?DEBUG(?MODULE_STRING " execute: Result: ~p\n", [ Result ]),
            case Result of 
                {badrpc, Reason} ->
                    {error, Reason};

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

            end;

        {error, _} = Error ->
            Error
            
    end.

get_node() ->
    case catch mnesia:dirty_read(hyd, node) of
        [{hyd, node, Node}] ->
            {ok, Node};

        [] ->
            ?DEBUG(?MODULE_STRING" hyd node is not set in  Mnesia...\n", []),
            {error, enoent};

        Error ->
            ?DEBUG(?MODULE_STRING" Can't retrieve node from Mnesia: ~p\n", [ Error ]),
            {error, Error}
    end.

extract(Path, Props) ->
    do_get(Path, Props, undefined).

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


