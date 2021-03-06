-module(hyd_fqids).
% Created hyd_fqids.erl the 02:14:53 (06/02/2014) on core
% Last Modification of hyd_fqids.erl at 09:15:17 (20/11/2015) on core
% 
% Author: "rolph" <rolphin@free.fr>

-export([
    reload/0
]).

-export([
    read/1, read/2,
    args/2, args/3,
    stats/1, stats/2,
    action/3
]).

-export([
    action_async/4
]).

-ifdef(TEST).
-export([
    test/0
]).
-endif.

%-define(debug, true).

-ifdef(debug).
-define(DEBUG(Format, Args),
  io:format(Format ++ " | ~w.~w\n",  Args ++ [?MODULE, ?LINE])).
-else.
-define(DEBUG(Format, Args), true).
-endif.

module() ->
    <<"fqids">>.

reload() ->
    hyd:reload( module() ).

% read information about an id
-spec read(
    FQID :: list() | binary(),
    Userid :: list() | binary() ) -> {ok, list()} | {error, term()}.

read(FQID, Userid) ->
    Ops = [
        hyd:operation(<<"read">>, module(), [ FQID, Userid ])
    ],
    run(Ops).

-spec read(
    Fqid :: list() | binary()) -> {ok, list()} | {error, term()}.

read(Fqid) ->
    Ops = [
        hyd:operation(<<"read">>, module(), [ Fqid ])
    ],
    run(Ops).

-spec stats(
    Fqid :: list() | binary()) -> {ok, list()} | {error, term()}.

stats(Fqid) ->
    Ops = [
        hyd:operation(<<"stats">>, module(), [ Fqid ])
    ],
    run(Ops).

-spec stats(
    FQID :: list() | binary(),
    Userid :: list() | binary() ) -> {ok, list()} | {error, term()}.

stats(FQID, Userid) ->
    Ops = [
        hyd:operation(<<"stats">>, module(), [ FQID, Userid ])
    ],
    run(Ops).

-spec args(
    Type :: list() | binary(),
    Method :: list() | binary()) -> {ok, list()} | {error, term()}.

args(Type, Method) ->
    Ops = [
        hyd:operation(<<"actionArgs">>, module(), [ Type, Method ])
    ],
    run(Ops).
    %parse_singleton(Ops).

-spec args(
    Type :: list() | binary(),
    Method :: list() | binary(),
    Userid :: list() | binary() ) -> list() | {error, term()}.

args(Type, <<"create">> = Method, Userid) ->
    Ops = [
        hyd:operation(<<"createArgs">>, module(), [ Type, Method, Userid ])
    ],
    case parse_indexed(Ops) of
        {ok, Result} ->
            Result;
        _Err ->
            _Err
    end;

args(Type, Method, Userid) ->
    Ops = [
        hyd:operation(<<"actionArgs">>, module(), [ Type, Method, Userid ])
    ],
    case parse_indexed(Ops) of
        {ok, Result} ->
            Result;
        _Err ->
            _Err
    end.

% Action on specific fqids
% If action is <<"create">>, create a new instance of Type
% Note: Fqid in this case is a type i.e. "message", or, "photo"
-spec action(
    Type :: list() | binary(),
    Action :: list() | binary(),
    Args :: list() ) -> list() | binary() | {error, term()}. 

action(Type, <<"create">>, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    Op = [
        hyd:operation(<<"create">>, module(), [ Type | FilteredArgs ])
    ],
    case parse_singleton(Op) of
        {ok, Result} ->
            Result;
        _Err ->
            _Err
    end;

action(Any, Action, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    Op = [
        hyd:operation(<<"action">>, module(), [ Any, Action | FilteredArgs ])
    ],
    run(Op).

% asynchronous version of action
action_async(TransId, Type, <<"create">>, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    db:cast(TransId, <<"create">>, module(), [ Type | FilteredArgs ]);

action_async(TransId, Any, Action, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    db:cast(TransId, <<"action">>, module(), [ Any, Action | FilteredArgs ]).

    %db:cast(100, <<"create">>,<<"fqids">>,[<<"article">>,[<<"1002">>,<<"!0003963828424TjwOyqDMPt0Kiw63828G9611">>,<<"My new idea of the day !">>,<<"Several environment variables control the operation of GT.M. Some of them must be set up for normal operation, where as for others GT.M assumes a default value if they are not set.">>,<<>>]]).


-spec run(
    Op :: [ tuple() ] ) -> list() | {error, term()}.

run(Op) ->
    case hyd:call(Op) of
        {ok, Elements } ->
            Results = lists:foldl( fun
                ({error, _} = Error, _Acc) ->
                    [ Error ];
                (X, Acc) ->
                    case db_results:unpack(X) of
                        {ok, Result} ->
                            [ Result | Acc ];

                        {ok, Infos, More} ->
                            case db_results:unpack(More) of
                                {ok, Result} ->
                                    [ {Infos, Result} | Acc ];

                                {error, _} = Error ->
                                    [ Error ]
                            end;

                        {error, _} = Error ->
                            [ Error ]
                    end
                end, [], Elements),
            lists:flatten(Results);
            
        _ ->
            internal_error(146)
    end.

-spec parse_indexed(
    Op :: [ tuple() ]) -> {ok, list()} | {error, term()}.

parse_indexed(Op) ->
    case run(Op) of
        [] ->
            {ok, []};

        [{error, _} = Error | _] ->
            ?DEBUG("Backend Error: ~p", [ Error ]),
            Error;

        [{_Index, _} | _] = Result ->
            ?DEBUG("Result: ~p", [Result]),
            Inversed = lists:map(fun({_,V}) ->
                V
            end, Result),
            {ok, lists:reverse( Inversed )};

        _Error ->
            % FIXME handle _Error
            ?DEBUG("Error: ~p", [ _Error ]),
            internal_error(161)
    end.

-spec parse_singleton(
    Op :: list([ term() ]) ) -> {ok, term()} | {error, term()}.

parse_singleton(Op) ->
    case run(Op) of
        [] ->
            {ok, []};

        [{error, _} = Error | _] ->
            ?DEBUG("Backend Error: ~p", [ Error ]),
            Error;

        [ Value | _] ->
            {ok, Value};

        _Error ->
            % FIXME handle _Error
            ?DEBUG("Error: ~p", [ _Error ]),
            internal_error(191)
    end.

internal_error(Code) ->
    internal_error(Code, []).

-spec internal_error(
    Code :: integer(),
    Args :: list() ) -> {error, term()}.

internal_error(Code, Args) ->
    hyd:error(?MODULE, Code, Args).

