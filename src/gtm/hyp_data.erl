%% Created hyp_data.erl the 18:00:15 (27/05/2015) on core
%% Last Modification of hyp_data.erl at 09:53:39 (10/06/2017) on core
%% 
%% @author rolph <rolphin@free.fr>
%% @doc Action API helpers.

-module(hyp_data).

-export([
    action/4,
    execute/3,
    extract/2
]).

-include("ejabberd.hrl").
-include("logger.hrl").

%% @doc Action entry point.
%% Execute an API call synchronously.

-spec action( 
    Userid :: non_neg_integer(),
    Fqid :: binary(),
    Action :: binary(),
    Args :: list(binary()) ) -> {error, term()} | {ok, term()}.

action(Userid, Fqid, Action, Args) ->
    ?DEBUG(?MODULE_STRING " action: Userid ~p, Action ~p, Args: ~p\n", [ Userid, Action, Args ]),
    execute( hyd_fqids, action, [ Fqid, Action, [ Userid | Args ] ]).

%% @doc Execute the API call.
%% Call synchronously the underlying api backend.

-spec execute( 
    Module :: binary(),
    Function :: binary(),
    Args :: list(binary()) ) -> {error, term()} | {ok, term()}.

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

%% @doc Extract keys from list of key value recursively.
%% Deep looking inside eventual lists of key value inside list of key values.
%% Perform something like XPath for key values.

-spec extract( 
    Path :: list(),
    Props :: list({binary(), binary()})) -> binary() | <<>>.

extract(Path, Props) ->
    do_get(Path, Props, <<>>).

%% @doc Implementation of recursive key value extractions.

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


